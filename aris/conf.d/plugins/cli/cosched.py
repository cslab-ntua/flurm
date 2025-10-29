from flux.cli.plugin import CLIPlugin
from math import ceil

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
            alloc_type = args.alloc_type
            if args.cosched:
                if alloc_type:
                    raise ValueError("Cannot specify -o alloc-type with --cosched")
                resources = jobspec.resource_counts()
                if not (resources.get('node') is None and resources.get('socket') is None):
                    raise ValueError("Cannot specify --alloc-type with resources other than cores/slots")
                nslots = {x[1]['label'] : x[2] for x in jobspec.resource_walk() if x[1]['type'] == 'slot'}
                ntasks = {task['slot']: (task['count']['total'] if task['count'].get('total') else task['count']['per_slot']*nslots[task['slot']]) for task in jobspec.tasks}
                if sum(ntasks.values()) > sum(nslots.values()):
                    raise ValueError("Cannot spread more tasks than available slots")
                # if for task number is not uniform across labels, we cannot spread
                if len(set(ntasks.values())) != 1:
                    raise ValueError("Cannot spread tasks with non-uniform task counts across labels")
                if len(ntasks) > 2:
                    raise ValueError("Cannot spread tasks across more than 2 labels")
                
                pps = 10
                nsockets = { label : ceil(ntasks[label]/(pps//2)) for label in ntasks.keys()} 
                jobspec.resources.clear()
                for label in ntasks.keys():
                    jobspec.resources.append({'type': 'socket', 'count': nsockets[label], 
                                              'with': [{'type': 'slot', 'count' : min(pps//2, ntasks[label]),  
                                                        'with': [{'type': 'core', 'count': 1}], 'label': label }] 
                                            })
                jobspec.setattr_shell_option("cpu-affinity", "per-task")
                for task in jobspec.tasks:
                    task['count'] = {'total': ntasks[task['slot']]} 
                jobspec.attributes["system"]["queue"] = "cosched"

        except KeyError as e:
            print(f"Error in allocation type plugin: {e}")