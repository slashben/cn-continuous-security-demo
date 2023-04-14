#  Continuous Security (CS) demo

Welcome to the documentation for our Cloud Native security demo that shows you to create policy objects from application behavior with ease. This demo showcases how you can seamlessly integrate this tool into your CI/CD pipelines, enabling you to generate network policy objects and Seccomp profile objects that meet your application's specific needs.

The demo utilizes Google's microservice-demo application, providing an excellent opportunity to see how our tool works in real-time. With the help of our tool, you can take your cloud-native application security to the next level, ensuring that your policies align with your application's behavior perfectly.

The documentation is designed to guide you through the process of using the tool and integrating it into your CI/CD pipelines. We have included step-by-step instructions on how to generate network policy objects and Seccomp profile objects, providing you with all the information you need to get started.

So, whether you are a seasoned developer or just starting with cloud-native applications, this demo is an excellent resource for you to explore. We hope you find this documentation helpful and easy to follow as you delve into the world of cloud-native security.

## Environment
* Linux host with `Minikube` & `Qemu` installed
* `kubectl`
* `yq` installed
* `bash`...
* Inspektor gadget installed

## Running the demo
Create a Minikube instance with:
```bash
./scripts/create-minikube.sh
```

If everything went OK, you can either run

```bash
./scripts/create-network-policies.sh 
```
to generate network policy objects in the [network-policies](/network-policies/) directory

or...

```bash
./scripts/create-seccomp-profiles.sh
```
to generate Seccomp profile objects in the [seccomp-profiles](/seccomp-profiles/) directory



