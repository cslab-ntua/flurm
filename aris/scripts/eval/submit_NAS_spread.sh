#! /bin/bash -l

# Half node cores
hnc=10

cases=(cg.D.64 ep.E.256 ft.D.256 mg.E.128) 
type="spread"

for case in "${cases[@]}";do

	IFS='.' read -r name class proc <<< "$case"

	nodes=$(( ${proc} / ${hnc} ))
	if (( $(( ${nodes} * ${hnc} )) < ${proc} ));then
		nodes=$(( ${nodes} + 1 ))
	fi

	echo "$app,$nodes"
	nodes=$((${nodes} + 1))
	sbatch --nodes=$nodes --partition=compute --time="00:12:00" --export=APP=$name,CLASS=$class,PROCS=$proc,ALLOC=$type flux_NAS.sh  

done