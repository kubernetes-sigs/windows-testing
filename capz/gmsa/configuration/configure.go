//go:build e2e
// +build e2e

package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/profiles/latest/compute/mgmt/compute"
	"github.com/Azure/azure-sdk-for-go/profiles/latest/network/mgmt/network"
	"github.com/Azure/azure-sdk-for-go/services/keyvault/v7.0/keyvault"
	"github.com/Azure/go-autorest/autorest/azure"
	"github.com/Azure/go-autorest/autorest/azure/auth"
	. "github.com/onsi/gomega" //nolint:revive
	"github.com/pkg/errors"
	"golang.org/x/crypto/ssh"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/controller-runtime/pkg/client"

	capz "sigs.k8s.io/cluster-api-provider-azure/azure"
	"sigs.k8s.io/cluster-api-provider-azure/test/e2e"

	corev1 "k8s.io/api/core/v1"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/util/retry"

	"sigs.k8s.io/cluster-api/test/framework"
)

func Fail(message string, _ ...int) {
	panic(message)
}

func main() {
	// needed for ginkgo
	RegisterFailHandler(Fail)

	// using a custom FlagSet here due to the dependency in controller-runtime that is already using this flag
	// https://github.com/kubernetes-sigs/controller-runtime/blob/c7a98aa706379c4e5c79ea675c7f333192677971/pkg/client/config/config.go#L37-L41
	fs := flag.NewFlagSet("logger", flag.ExitOnError)

	// required flags
	clustername := fs.String("name", "", "Name of the workload cluster to collect logs for")

	// optional flags that default
	namespace := fs.String("namespace", "", "namot include the command name. Must be called after all flags in the FlagSet are defined and before flags are accessed by the program. The return value will be ErrHelp if -help or -h were set buespace on management cluster to collect logs for")
	kubeconfigPath := fs.String("kubeconfig", getKubeConfigPath(), "The kubeconfig for the management cluster")

	if err := fs.Parse(os.Args[1:]); err != nil {
		fmt.Println("Unable to parse command flags")
		os.Exit(1)
	}

	// use the cluster name as the namespace which is default in e2e tests
	if *namespace == "" {
		namespace = clustername
	}

	bootstrapClusterProxy := e2e.NewAzureClusterProxy("bootstrap", *kubeconfigPath)
	configureGmsa(context.Background(), bootstrapClusterProxy, *namespace, *clustername)
}

func getKubeConfigPath() string {
	config := os.Getenv("KUBECONFIG")
	if config == "" {
		d, err := os.UserHomeDir()
		Expect(err).NotTo(HaveOccurred())
		return path.Join(d, ".kube", "config")
	}

	return config
}

func configureGmsa(ctx context.Context, bootstrapClusterProxy framework.ClusterProxy, namespace, clusterName string) {
	settings, err := auth.GetSettingsFromEnvironment()
	Expect(err).NotTo(HaveOccurred())
	authorizer, err := settings.GetAuthorizer()
	Expect(err).NotTo(HaveOccurred())
	subID := settings.GetSubscriptionID()

	Expect(err).NotTo(HaveOccurred())
	keyVaultClient := keyvault.New()

	vmClient := compute.NewVirtualMachinesClient(subID)
	vmClient.Authorizer = authorizer

	networkClient := network.NewVirtualNetworkPeeringsClient(subID)
	networkClient.Authorizer = authorizer

	// override to use keyvault management endpoint
	settings.Values[auth.Resource] = fmt.Sprintf("%s%s", "https://", azure.PublicCloud.KeyVaultDNSSuffix)
	keyvaultAuthorizer, err := settings.GetAuthorizer()
	Expect(err).NotTo(HaveOccurred())
	keyVaultClient.Authorizer = keyvaultAuthorizer

	workloadProxy := bootstrapClusterProxy.GetWorkloadCluster(ctx, namespace, clusterName)

	// Wait for the Domain to finish provisioning.  The existence of the spec file is the marker
	gmsaSpecName := "gmsa-cred-spec-gmsa-e2e-" + os.Getenv("GMSA_ID")
	fmt.Printf("INFO: Getting the gmsa gmsaSpecFile %s from %s\n", gmsaSpecName, os.Getenv("GMSA_KEYVAULT_URL"))
	var gmsaSpecFile keyvault.SecretBundle
	Eventually(func() error {
		gmsaSpecFile, err = keyVaultClient.GetSecret(ctx, os.Getenv("GMSA_KEYVAULT_URL"), gmsaSpecName, "")
		if capz.ResourceNotFound(err) {
			fmt.Printf("INFO: Waiting for gmsaSpecFile %s to be created by Domain controller\n", os.Getenv("GMSA_KEYVAULT_URL"))
			return err
		}

		if err != nil {
			fmt.Printf("INFO: error when retrieving gmsaSpecFile %s\n", err)
			return err
		}
		return nil
	}, 10*time.Second, 15*time.Minute).Should(Succeed())
	Expect(gmsaSpecFile.Value).ToNot(BeNil())

	workloadCluster, err := util.GetClusterByName(ctx, bootstrapClusterProxy.GetClient(), namespace, clusterName)
	Expect(err).NotTo(HaveOccurred())
	clusterHostName := workloadCluster.Spec.ControlPlaneEndpoint.Host

	gmsaNode, windowsNodes := labelGmsaTestNode(ctx, workloadProxy)
	dropGmsaSpecOnTestNode(gmsaNode, clusterHostName, gmsaSpecFile)
	configureCoreDNS(ctx, workloadProxy)

	for _, n := range windowsNodes.Items {
		hostname := getHostName(&n)
		// until https://github.com/kubernetes-sigs/cluster-api-provider-azure/issues/2182
		updateWorkerNodeDNS(clusterHostName, hostname)
	}

	fmt.Printf("INFO: GMSA configuration complete\n")
}

func updateWorkerNodeDNS(clusterHostName string, workerNodeHostName string) {

	fmt.Printf("INFO: Update node vm dns to %s\n", os.Getenv("GMSA_DNS_IP"))
	dnsCmd := fmt.Sprintf("$currentDNS = (Get-DnsClientServerAddress -AddressFamily ipv4); Set-DnsClientServerAddress -InterfaceIndex $currentDNS[0].InterfaceIndex -ServerAddresses %s, $currentDNS[0].Address", os.Getenv("GMSA_DNS_IP"))
	f, err := fileOnHost(filepath.Join("", "gmsa-spec-writer-output.txt"))
	Expect(err).NotTo(HaveOccurred())
	defer f.Close()
	err = execOnHost(clusterHostName, workerNodeHostName, "22", f, dnsCmd)
	Expect(err).NotTo(HaveOccurred())
}

func configureCoreDNS(ctx context.Context, workloadProxy framework.ClusterProxy) {
	fmt.Printf("INFO: Update coredns with domain ip %s\n", os.Getenv("GMSA_DNS_IP"))

	corednsConfigMap := &corev1.ConfigMap{}
	key := client.ObjectKey{
		Namespace: "kube-system",
		Name:      "coredns",
	}
	err := workloadProxy.GetClient().Get(ctx, key, corednsConfigMap)
	Expect(err).NotTo(HaveOccurred())

	corefile, ok := corednsConfigMap.Data["Corefile"]
	Expect(ok).Should(BeTrue())

	gmsaDNS := fmt.Sprintf(`k8sgmsa.lan:53 {
	errors
	cache 30
	log
	forward . %s
}`, os.Getenv("GMSA_DNS_IP"))

	corefile += gmsaDNS
	corednsConfigMap.Data["Corefile"] = corefile
	err = workloadProxy.GetClient().Update(ctx, corednsConfigMap)
	Expect(err).NotTo(HaveOccurred())

	// rollout restart to refresh the configuration
	patch := []byte(`{"spec": {"template":{ "metadata": { "annotations": { "restartedBy": "gmsa" } } } } }`)
	_, err = workloadProxy.GetClientSet().AppsV1().Deployments("kube-system").Patch(ctx, "coredns", types.MergePatchType, patch, v1.PatchOptions{})
	Expect(err).NotTo(HaveOccurred())
}

func dropGmsaSpecOnTestNode(gmsaNode *corev1.Node, clusterHostName string, secret keyvault.SecretBundle) {
	fmt.Printf("INFO: Writing gmsa spec to disk\n")
	f, err := fileOnHost(filepath.Join("", "gmsa-spec-writer-output.txt"))
	Expect(err).NotTo(HaveOccurred())
	defer f.Close()
	hostname := getHostName(gmsaNode)

	cmd := fmt.Sprintf("mkdir -force /gmsa; rm -force c:/gmsa/gmsa-cred-spec-gmsa-e2e.yml; $input='%s'; [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($input)) >> c:/gmsa/gmsa-cred-spec-gmsa-e2e.yml", *secret.Value)
	err = execOnHost(clusterHostName, hostname, "22", f, cmd)
	Expect(err).NotTo(HaveOccurred())
}

func labelGmsaTestNode(ctx context.Context, workloadProxy framework.ClusterProxy) (*corev1.Node, *corev1.NodeList) {
	windowsNodeOptions := v1.ListOptions{
		LabelSelector: "kubernetes.io/os=windows",
	}

	var gmsaNode *corev1.Node
	var windowsNodes *corev1.NodeList
	var err error
	err = retry.RetryOnConflict(retry.DefaultRetry, func() error {
		windowsNodes, err = workloadProxy.GetClientSet().CoreV1().Nodes().List(ctx, windowsNodeOptions)
		if err != nil {
			return err
		}

		Expect(len(windowsNodes.Items)).Should(BeNumerically(">", 0))
		gmsaNode = &windowsNodes.Items[0]
		gmsaNode.Labels["agentpool"] = "windowsgmsa"
		fmt.Printf("INFO: Labeling node %s as 'windowsgmsa'\n", gmsaNode.Name)
		_, err = workloadProxy.GetClientSet().CoreV1().Nodes().Update(ctx, gmsaNode, v1.UpdateOptions{})
		return err
	})
	Expect(err).NotTo(HaveOccurred())
	Expect(gmsaNode).NotTo(BeNil())
	return gmsaNode, windowsNodes
}

func getHostName(gmsaNode *corev1.Node) string {
	hostname := ""
	for _, address := range gmsaNode.Status.Addresses {
		if address.Type == corev1.NodeHostName {
			hostname = address.Address
		}
	}
	return hostname
}

func fileOnHost(path string) (*os.File, error) {
	if err := os.MkdirAll(filepath.Dir(path), os.ModePerm); err != nil {
		return nil, err
	}

	return os.Create(path)
}

func execOnHost(controlPlaneEndpoint, hostname, port string, f io.StringWriter, command string,
	args ...string) error {
	config, err := newSSHConfig()
	if err != nil {
		return err
	}

	// Init a client connection to a control plane node via the public load balancer
	lbClient, err := ssh.Dial("tcp", fmt.Sprintf("%s:%s", controlPlaneEndpoint, port), config)
	if err != nil {
		return errors.Wrapf(err, "dialing public load balancer at %s", controlPlaneEndpoint)
	}

	// Init a connection from the control plane to the target node
	c, err := lbClient.Dial("tcp", fmt.Sprintf("%s:%s", hostname, port))
	if err != nil {
		return errors.Wrapf(err, "dialing from control plane to target node at %s", hostname)
	}

	// Establish an authenticated SSH conn over the client -> control plane -> target transport
	conn, chans, reqs, err := ssh.NewClientConn(c, hostname, config)
	if err != nil {
		return errors.Wrap(err, "getting a new SSH client connection")
	}
	client := ssh.NewClient(conn, chans, reqs)
	session, err := client.NewSession()
	if err != nil {
		return errors.Wrap(err, "opening SSH session")
	}
	defer session.Close()

	// Run the command and write the captured stdout to the file
	var stdoutBuf bytes.Buffer
	session.Stdout = &stdoutBuf
	if len(args) > 0 {
		command += " " + strings.Join(args, " ")
	}
	if err = session.Run(command); err != nil {
		return errors.Wrapf(err, "running command \"%s\"", command)
	}
	if _, err = f.WriteString(stdoutBuf.String()); err != nil {
		return errors.Wrap(err, "writing output to file")
	}

	return nil
}

// newSSHConfig returns an SSH config for a workload cluster in the current e2e test run.
func newSSHConfig() (*ssh.ClientConfig, error) {
	// find private key file used for e2e workload cluster
	keyfile := os.Getenv("AZURE_SSH_PUBLIC_KEY_FILE")
	if len(keyfile) > 4 && strings.HasSuffix(keyfile, "pub") {
		keyfile = keyfile[:(len(keyfile) - 4)]
	}
	if keyfile == "" {
		keyfile = ".sshkey"
	}
	if _, err := os.Stat(keyfile); os.IsNotExist(err) {
		if !filepath.IsAbs(keyfile) {
			// current working directory may be test/e2e, so look in the project root
			keyfile = filepath.Join("..", "..", keyfile)
		}
	}

	pubkey, err := publicKeyFile(keyfile)
	if err != nil {
		return nil, err
	}
	sshConfig := ssh.ClientConfig{
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		User:            "capi",
		Auth:            []ssh.AuthMethod{pubkey},
	}
	return &sshConfig, nil
}

// publicKeyFile parses and returns the public key from the specified private key file.
func publicKeyFile(file string) (ssh.AuthMethod, error) {
	buffer, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	signer, err := ssh.ParsePrivateKey(buffer)
	if err != nil {
		return nil, err
	}
	return ssh.PublicKeys(signer), nil
}
