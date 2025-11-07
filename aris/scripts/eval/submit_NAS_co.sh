#! /bin/bash -l

# Half node cores
hnc=10

cases=(cg.D.64_cg.D.64 cg.D.64_ep.E.256 cg.D.64_ft.D.256 cg.D.64_mg.E.128 ep.E.256_ep.E.256)
#(ep.E.256_ft.D.256 ep.E.256_mg.E.128 ft.D.256_ft.D.256 ft.D.256_mg.E.128 mg.E.128_mg.E.128)
type="co"
for case in "${cases[@]}";do

	IFS='_' read -r app app2 <<< "$case"
	IFS='.' read -r name class proc <<< "$app"
	IFS='.' read -r name2 class2 proc2 <<< "$app2"

	if (( ${proc} >= ${proc2} ));then
		maxprocs=${proc}
		minprocs=${proc2}
	else
		maxprocs=${proc2}
		minprocs=${proc}
	fi

	copies=$(( ${maxprocs} / ${minprocs} ))
	minapp_nodes=$(( ${minprocs} / ${hnc} ))
	if (( $(( ${minapp_nodes} * ${hnc} )) < ${minprocs} ));then
		minapp_nodes=$(( ${minapp_nodes} + 1 ))
	fi

	maxapp_nodes=$(( ${maxprocs} / ${hnc} ))
	if (( $(( ${maxapp_nodes} * ${hnc} )) < ${maxprocs} ));then
		maxapp_nodes=$(( ${maxapp_nodes} + 1 ))
	fi

	if (( ${maxapp_nodes} >= $(( ${minapp_nodes} * ${copies} )) ));then
		nodes=${maxapp_nodes}
	else
		nodes=$(( ${minapp_nodes} * ${copies} )) 
	fi
	
	echo "$app,$app2,$nodes,$copies,$minapp_nodes,$maxapp_nodes"
	nodes=$((${nodes} + 1))
	sbatch --nodes=$nodes --partition=compute --time="00:12:00" --export=APP=$name,CLASS=$class,PROCS=$proc,APP2=$name2,CLASS2=$class2,PROCS2=$proc2,ALLOC=$type flux_NAS.sh 

done