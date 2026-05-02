import subprocess
from math import ceil
from flux import Flux

class CoSchedPlugin(CLIPlugin):
    """Flux cli alloc-type plugin. Modifies the job spec to the appropriate resource allocation type."""
    # def add_options(self, parser):
    #     print("Adding alloc-type plugin options")
    #     parser.add_argument("--alloc-type", type=str, help="Choose the allocation type")
    def __init__(self, prog, prefix=None):
        super().__init__(prog, prefix=prefix)
        self.add_option(
            "--cosched",
            action="store_true",
            help="Enable co-scheduling and send job to cosched queue",
        )
    def modify_jobspec(self, args, jobspec):
        try:
            if Flux().conf_get('cosched.allowed') == True:
                print(Flux().conf_get('cosched.allowed'))
                if len(jobspec.tasks) != 1:
                    raise ValueError("Multiple slot labels in the same request are not allowed for co-scheduling")
                task_count = jobspec.tasks[0]['count']
                ntasks = 0
                nslots = 1
                label = ""
                per_resource = {}
                print(task_count)
                for parent, resource, count in jobspec.resource_walk():
                    if parent and parent['type'] != 'slot':
                        raise ValueError("Can only co-schedule requests with only resources of the lowest hierarchy specified")
                    if resource['type'] == 'slot':
                        label = resource['label']
                        for ttype, tcount in task_count.items():
                            if ttype == 'per_slot':
                                ntasks = tcount * count
                                nslots = count
                            elif ttype == 'per_resource':
                                for rtype, rcount in tcount.items():
                                    per_resource[rtype] = rcount
                                nslots = count
                            else:
                                ntasks = tcount
                                nslots = count
                    if resource['type'] in per_resource:
                        ntasks += per_resource[resource['type']] * count


                output = subprocess.check_output("lscpu", shell=True).decode()
                info = {}
                for line in output.splitlines():
                    if ":" in line:
                        key, value = line.split(":", 1)
                        info[key.strip()] = value.strip()

                sockets = int(info.get("Socket(s)", 1))
                numa_nodes = int(info.get("NUMA node(s)", 1))
                cores_per_socket = int(info.get("Core(s) per socket", 1))

                numa_per_socket = numa_nodes // sockets
                cores_per_numa = cores_per_socket // numa_per_socket

                jobspec.resources.clear()
                jobspec.resources.append({'type': 'numanode', 'count': ceil (nslots / (cores_per_numa // 2)),
                                              'with': [{'type': 'slot', 'count' : min (cores_per_numa // 2, nslots),
                                                        'with': [{'type': 'core', 'count': 1}], 'label': label }]
                                            })

                jobspec.tasks[0]['count'] = {'total': ntasks}
                print(jobspec.resources)
                print(jobspec.tasks)
        except KeyError as e:
            print(f"Error in allocation type plugin: {e}")