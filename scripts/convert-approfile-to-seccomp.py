import yaml
import json
import sys

def main():
    # Approfile file is the first argument
    approfile = sys.argv[1]
    with open(approfile, 'r') as f:
        approfile = yaml.safe_load(f)

        seccompobject = {
            'kind': 'SeccompProfile',
            'apiVersion': 'spdx.softwarecomposition.kubescape.io/v1beta1',
            'metadata': {
                'name': f'{approfile['metadata']['labels']['kubescape.io/workload-kind'].lower()}-{approfile['metadata']['labels']['kubescape.io/workload-name']}',
                'namespace': approfile['metadata']['namespace']
            },
            'spec': {
                'containers': []
            }
        }

        for container in approfile['spec']['containers']:
            containerobject = {
                'name': container['name'],
                'path': f'{approfile['metadata']['namespace']}/{approfile['metadata']['labels']['kubescape.io/workload-kind']}-{approfile['metadata']['labels']['kubescape.io/workload-name']}-{container['name']}.json',
                'spec': {
                    'defaultAction': 'SCMP_ACT_ERRNO',
                    'syscalls': [{
                        'names': container['syscalls'],
                        'action': 'SCMP_ACT_ALLOW'
                    }],
                    'architectures': ['SCMP_ARCH_X86_64', 'SCMP_ARCH_X86', 'SCMP_ARCH_X32']
                }
            }

            seccompobject['spec']['containers'].append(containerobject)

        print(yaml.dump(seccompobject))

if __name__ == '__main__':
    main()