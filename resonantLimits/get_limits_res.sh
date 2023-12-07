#!/usr/bin/env bash                                                                                                                        
declare -a CHANNELS;
declare -a SELECTIONS;
declare -a MASSES;
declare -a MASSES_INJ;

# Defaults
TAG=""
VAR="DNNoutSM_kl_1"
SIGNAL="ggFRadion"
DRYRUN="0"
MODE=""
MODE_CHOICES=( "separate" "sel_group" "chn_group" "all_group" "sel_years" "chn_years" "all_years" )
BASEDIR="${HOME}/CMSSW_11_1_9/src/KLUBAnalysis"
EXPECTED_SIGNAL=0.3

HELP_STR="Prints this help message."
TAG_STR="(String) Defines tag for the output. Defaults to '${TAG}'."
MODE_STR="(String) Defines the mode. Defaults to '${MODE}'."
VAR_STR="(String) Variable to use for the likelihood fit."
SIGNAL_STR="(String) Signal sample type."
DRYRUN_STR="(Boolean) Whether to run in dry-run mode. Defaults to '${DRYRUN}'."
MASSES_STR="(Array of ints) Resonant masses."
MASSES_INJ_STR="(Array of ints) Resonant masses with injected signal."
CHANNELS_STR="(Array of strings) Channels."
SELECTIONS_STR="(Array of strings) Selection categories."
EXP_SIGNAL_STR="(Float) Expected signal in signal strength units. Defaults to '${EXPECTED_SIGNAL}'."
BASEDIR_STR="(String) Base directory."
function print_usage_submit_skims {
    USAGE="

    Run example: bash $(basename "$0") -t <some_tag>
                                      
    -h / --help       [${HELP_STR}]
    -m / --mode       [${MODE_STR}]
    -t / --tag        [${TAG_STR}]
    -b / --base       [${BASEDIR_STR}]
    -v / --var        [${VAR_STR}]
    -s / --signal     [${SIGNAL_STR}]
    -c / --channels   [${CHANNELS_STR}] 
    -m / --masses     [${MASSES_STR}]
    -i / --injection  [${MASSES_INJ_STR}]
    -l / --selections [${SELECTIONS_STR}]
	-e / --expsignal  [${EXPECTED_SIGNAL}] 
    -n / --dryrun     [${DRYRUN_STR}]      

"
    printf "${USAGE}"
}

while [[ $# -gt 0 ]]; do
    key=${1}
    case $key in
        -h|--help)
            print_usage_submit_skims
            exit 1
            ;;
        -t|--tag)
            TAG=${2}
            shift; shift;
            ;;
		-b|--base)
			BASEDIR=${2}
			shift; shift;
			;;
		--mode)
			MODE=${2}
			if [[ ! " ${MODE_CHOICES[*]} " =~ " ${MODE} " ]]; then
				echo "You provided mode=${MODE}."
				echo "Currently the following modes are supported:"
				for md in ${MODE_CHOICES[@]}; do
					echo "- ${md}" # bash string substitution
				done
				exit 1;
			fi
			shift; shift;
			;;
		-s|--signal)
            SIGNAL=${2}
            shift; shift;
            ;;
		-v|--var)
            VAR=${2}
            shift; shift;
            ;;
        -m|--masses)
            mass_flag=0
            while [ ${mass_flag} -eq 0 ]; do
                if [[ "${2}" =~ ^[-].*$ ]] || [[ "${2}" =~ ^$ ]]; then
                    mass_flag=1
                else
                    MASSES+=(${2});
                    shift;
                fi
            done
            shift;
            ;;
        -i|--injection)
            inj_flag=0
            while [ ${inj_flag} -eq 0 ]; do
                if [[ "${2}" =~ ^[-].*$ ]] || [[ "${2}" =~ ^$ ]]; then
                    inj_flag=1
                else
                    MASSES_INJ+=(${2});
                    shift;
                fi
            done
            shift;
            ;;
        -c|--channels)
            chn_flag=0
            while [ ${chn_flag} -eq 0 ]; do
                if [[ "${2}" =~ ^[-].*$ ]] || [[ "${2}" =~ ^$ ]]; then
                    chn_flag=1
                else
                    CHANNELS+=(${2});
                    shift;
                fi
            done
            shift;
            ;;
        -l|--selections)
            sel_flag=0
            while [ ${sel_flag} -eq 0 ]; do
                if [[ "${2}" =~ ^[-].*$ ]] || [[ "${2}" =~ ^$ ]]; then
                    sel_flag=1
                else
                    SELECTIONS+=(${2});
                    shift;
                fi
            done
            shift;
            ;;
		-e|--expsignal)
            EXPECTED_SIGNAL=${2}
            shift; shift;
            ;;
        -c|--channels)
            chn_flag=0
            while [ ${chn_flag} -eq 0 ]; do
                if [[ "${2}" =~ ^[-].*$ ]] || [[ "${2}" =~ ^$ ]]; then
                    chn_flag=1
                else
                    CHANNELS+=(${2});
                    shift;
                fi
            done
            shift;
            ;;
		-n|--dryrun)
			DRYRUN="1"
			shift;
			;;
        *) # unknown option
	    echo "Wrong parameter ${1}."
            exit 1
            ;;
    esac
done

if [[ -z ${MODE} ]]; then
    echo "Select the data period via the '--mode' option."
    exit 1;
fi

if [ ${#MASSES[@]} -eq 0 ]; then
    MASSES_DEFAULT=("250" "260" "270" "280" "300" "320" "350" "400" "450" "500" "550" "600" "650" "700" "750" "800" "850" "900" "1000" "1250" "1500" "1750" "2000" "2500" "3000")
	for mass in ${MASSES_DEFAULT[@]}; do
		inside=0
		for elem in "${MASSES_INJ[@]}"; do
			[[ $mass == "$elem" ]] && inside=1;
		done
		if [ ${inside} -eq 0 ]; then
			MASSES+=(${mass})
		fi
	done
fi
if [ ${#CHANNELS[@]} -eq 0 ]; then
    CHANNELS=("ETau" "MuTau" "TauTau")
fi
if [ ${#SELECTIONS[@]} -eq 0 ]; then
    SELECTIONS=("s1b1jresolvedMcut" "s2b0jresolvedMcut" "sboostedLLMcut")
fi

declare -a MHIGH;
for mass in ${MASSES[@]}; do
    if [ ${mass} -gt "319" ]; then
	MHIGH+=(${mass})
    fi
done
if [ ${#MASSES_INJ[@]} -ne 0 ]; then
	declare -a MHIGH_INJ;
	for mass in ${MASSES_INJ[@]}; do
		if [ ${mass} -gt "319" ]; then
			MHIGH_INJ+=(${mass})
		fi
	done
fi

# generate Asimov dataset for all points if injection is requested
# for at least one mass point
if [ ${#MASSES_INJ[@]} -ne 0 ]; then
	COMM_INJ=" -t -1 "
else
	COMM_INJ=" ${COMM_INJ} "
fi

declare -a CATEGORIES_BOOST;
declare -a CATEGORIES_NOBOOST;
for sel in ${SELECTIONS[@]}; do
    if [[ ${sel} =~ .*boosted.* ]]; then
	CATEGORIES_BOOST+=(${sel})
    else
	CATEGORIES_NOBOOST+=(${sel})
    fi
done

LIMIT_DIR="${BASEDIR}/resonantLimits"
IDENTIFIER=".test_${SIGNAL}_${VAR}"

if [ ${MODE} == "separate" ]; then
    
    for i in "${!CHANNELS[@]}"; do
	card_dir="${LIMIT_DIR}/cards_${TAG}_${CHANNELS[$i]}"
	cd ${card_dir}
	
	printf "Processing categories in parallel for channel ${CHANNELS[$i]} "
	printf "(mode ${MODE}, var ${VAR})...\n"
	
	out_="combined_out"
	for sel in ${SELECTIONS[@]}; do
	    cat_dir="${card_dir}/${sel}_${VAR}"
	    out_dir="${cat_dir}/${out_}"
	    mkdir -p "${out_dir}"
	done
	
	cat_dir_parallel="${card_dir}/{2}_${VAR}"
	out_dir_parallel="${cat_dir_parallel}/${out_}"
	
	# parallellize across the mass and category
	proc="${SIGNAL}_${VAR}_{1}"
	in_txt="${cat_dir_parallel}/comb.${proc}.txt"
	out_log="${out_dir_parallel}/comb.${proc}.log"
	
	parallel rm -f -- ${out_log} ::: ${MASSES[@]} ::: ${SELECTIONS[@]}
	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		parallel rm -f -- ${out_log} ::: ${MASSES_INJ[@]} ::: ${SELECTIONS[@]}
	fi

	if [ ${#CATEGORIES_BOOST[@]} -ne 0 ]; then
	    parallel -j $((`nproc` - 1)) \
		combine -M AsymptoticLimits ${in_txt} \
		-n ${IDENTIFIER}_{2} \
		${COMM_INJ} \
		--freezeParameters SignalScale \
		-m {1} ">" ${out_log} ::: ${MHIGH[@]} ::: ${CATEGORIES_BOOST[@]}
	fi
	
	if [ ${#CATEGORIES_NOBOOST[@]} -ne 0 ]; then
	    parallel -j $((`nproc` - 1)) \
		combine -M AsymptoticLimits ${in_txt} \
		-n ${IDENTIFIER}_{2} \
		${COMM_INJ} \
		--freezeParameters SignalScale \
		-m {1} ">" ${out_log} ::: ${MASSES[@]} ::: ${CATEGORIES_NOBOOST[@]}
	fi

	if [ ${#MHIGH_INJ[@]} -ne 0 ]; then
		if [ ${#CATEGORIES_BOOST[@]} -ne 0 ]; then
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_{2} \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MHIGH_INJ[@]} ::: ${CATEGORIES_BOOST[@]}
		fi
	fi	

	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		if [ ${#CATEGORIES_NOBOOST[@]} -ne 0 ]; then
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_{2} \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]} ::: ${CATEGORIES_NOBOOST[@]}
		fi
	fi

	cd -
    done

elif [ ${MODE} == "sel_group" ]; then
    
    for chn in "${CHANNELS[@]}"; do
	echo "Processing channel ${chn} with mode ${MODE} (var ${VAR})..."
	card_dir="${LIMIT_DIR}/cards_${TAG}_${chn}"
	
	comb_dir="${card_dir}/comb_cat/AllCategories/"
	cd ${comb_dir}
	
	out_dir="${comb_dir}/combined_out"
	mkdir -p "${out_dir}"
	
	# parallellize across the mass
	proc="${SIGNAL}_${VAR}_{1}"
	in_txt="${comb_dir}/comb.${proc}.txt"
	out_log="${out_dir}/comb.${proc}.log"

	parallel -j 0 rm -f -- ${out_log} ::: ${MASSES[@]}
	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		parallel -j 0 rm -f -- ${out_log} ::: ${MASSES_INJ[@]}
	fi

	parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_${chn} \
				 ${COMM_INJ} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MASSES[@]}

	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_${chn} \
				 ${COMM_INJ} \
				 --expectSignal ${EXPECTED_SIGNAL} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]}
	fi

	cd -
	
	# group categories according to selections passed by the user
	for selp in ${SELECTIONS[@]}; do
	    comb_dir="${card_dir}/comb_cat/${selp}_${VAR}/"
	    cd ${comb_dir}
	    
	    out_dir="${comb_dir}/combined_out"
	    mkdir -p "${out_dir}"
	    
	    # parallellize across the mass
	    proc="${SIGNAL}_${VAR}_{1}"
	    in_txt="${comb_dir}/comb.${proc}.txt"
	    out_log="${out_dir}/comb.${proc}.log"
	    
	    parallel -j 0 rm -f -- ${out_log} ::: ${MASSES[@]}
		if [ ${#MASSES_INJ[@]} -ne 0 ]; then
			parallel -j 0 rm -f -- ${out_log} ::: ${MASSES_INJ[@]}
		fi

		
	    if [[ ${selp} =~ .*resolved.* ]]; then

			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_${chn} \
					 ${COMM_INJ} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MASSES[@]}
			if [ ${#MASSES_INJ[@]} -ne 0 ]; then
				parallel -j $((`nproc` - 1)) \
						 combine -M AsymptoticLimits ${in_txt} \
						 -n ${IDENTIFIER}_${chn} \
						 ${COMM_INJ} \
						 --expectSignal ${EXPECTED_SIGNAL} \
						 --freezeParameters SignalScale \
						 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]}
			fi
			
	    else

			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_${chn} \
					 ${COMM_INJ} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MHIGH[@]}
			if [ ${#MASSES_INJ[@]} -ne 0 ]; then
				parallel -j $((`nproc` - 1)) \
						 combine -M AsymptoticLimits ${in_txt} \
						 -n ${IDENTIFIER}_${chn} \
						 ${COMM_INJ} \
						 --expectSignal ${EXPECTED_SIGNAL} \
						 --freezeParameters SignalScale \
						 -m {1} ">" ${out_log} ::: ${MHIGH_INJ[@]}
			fi

		fi
	    
	    cd -
	    
	done
    done


elif [ ${MODE} == "chn_group" ]; then
    
    echo "Processing category ${sel} with mode ${MODE} (var ${VAR})..."
    card_dir="${LIMIT_DIR}/cards_${TAG}_CombChn"
    cd ${card_dir}
    out_="combined_out"

    for sel in ${SELECTIONS[@]}; do
		comb_dir="${card_dir}/${sel}_${VAR}"
		out_dir="${comb_dir}/${out_}"
		mkdir -p "${out_dir}"
    done

    comb_dir_parallel="${card_dir}/{2}_${VAR}"
    out_dir_parallel="${comb_dir_parallel}/${out_}"
    
    # parallellize across the mass and categories
    proc="${SIGNAL}_${VAR}_{1}"
    in_txt="${comb_dir_parallel}/comb.${proc}.txt"
    out_log="${out_dir_parallel}/comb.${proc}.log"
	parallel -j 0 rm -f -- ${out_log} ::: ${MASSES[@]} ::: ${SELECTIONS[@]}
	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		parallel -j 0 rm -f -- ${out_log} ::: ${MASSES_INJ[@]} ::: ${SELECTIONS[@]}
	fi

	
    if [ ${#CATEGORIES_BOOST[@]} -ne 0 ]; then
		
		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_{2} \
				 ${COMM_INJ} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MHIGH[@]} ::: ${CATEGORIES_BOOST[@]}

		if [ ${#MASSES_INJ[@]} -ne 0 ]; then
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_{2} \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MHIGH_INJ[@]} ::: ${CATEGORIES_BOOST[@]}
		fi
    fi
    
    if [ ${#CATEGORIES_NOBOOST[@]} -ne 0 ]; then

		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_{2} \
				 ${COMM_INJ} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MASSES[@]} ::: ${CATEGORIES_NOBOOST[@]}

		if [ ${#MASSES_INJ[@]} -ne 0 ]; then
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_{2} \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]} ::: ${CATEGORIES_NOBOOST[@]}
		fi
    fi
    
    cd -

elif [ ${MODE} == "all_group" ]; then

    echo "Processing all categories and channels (mode ${MODE}, var ${VAR})..."
    card_dir="${LIMIT_DIR}/cards_${TAG}_All"
    cd ${card_dir}

    out_dir="${card_dir}/combined_out"
    mkdir -p "${out_dir}"

    # parallellize across the mass
    proc="${SIGNAL}_${VAR}_{1}"
    in_txt="${card_dir}/comb.${proc}.txt"
    out_log="${out_dir}/comb.${proc}.log"

    parallel -j 0 rm -f -- ${out_log} ::: ${MASSES[@]}
	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		parallel -j 0 rm -f -- ${out_log} ::: ${MASSES_INJ[@]}
	fi 

	declare -a COMMS_WRITE;
	for minj in ${MASSES[@]}; do
		proc="${SIGNAL}_${VAR}_${minj}"
		in_txt="${card_dir}/comb.${proc}.txt"
		out_log="${out_dir}/comb.${proc}.log"
		COMMS_WRITE+=("combine -M AsymptoticLimits ${in_txt} -n ${IDENTIFIER}_all ${COMM_INJ} --freezeParameters SignalScale -m ${minj} > ${out_log}")
	done
    [[ ${DRYRUN} -eq 1 ]] && parallel echo {} ::: "${COMMS_WRITE}" || parallel -j $((`nproc` - 1)) {} ::: "${COMMS_WRITE[@]}"

	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		declare -a COMMS_WRITE;
		for minj in ${MASSES_INJ[@]}; do
			proc="${SIGNAL}_${VAR}_${minj}"
			in_txt="${card_dir}/comb.${proc}.txt"
			out_log="${out_dir}/comb.${proc}.log"
			COMMS_WRITE+=("combine -M AsymptoticLimits ${in_txt} -n ${IDENTIFIER}_all ${COMM_INJ} --expectSignal ${EXPECTED_SIGNAL} --freezeParameters SignalScale -m ${minj} > ${out_log}")
		done
		[[ ${DRYRUN} -eq 1 ]] && parallel echo {} ::: "${COMMS_WRITE}" || parallel -j $((`nproc` - 1)) {} ::: "${COMMS_WRITE[@]}"
	fi
		
elif [ ${MODE} == "sel_years" ]; then
    card_dir="${LIMIT_DIR}/cards_Years_${VAR}_CombCat"
    cd ${card_dir}

    for chn in "${CHANNELS[@]}"; do
		echo "Channel ${chn}: Processing all years and categories (mode ${MODE}, var ${VAR})..."
		
		comb_dir="${card_dir}/${chn}"
		out_dir="${comb_dir}/combined_out"
		mkdir -p "${out_dir}"
		
		proc="${SIGNAL}_${VAR}_{1}"
		in_txt="${comb_dir}/comb.${proc}.txt"
		out_log="${out_dir}/comb.${proc}.log"

		# parallellize across the mass
		parallel -j 0 rm -f -- ${out_log} ::: ${MASSES[@]}
		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_years \
				 ${COMM_INJ} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MASSES[@]}

		if [ ${#MASSES_INJ[@]} -ne 0 ]; then
			parallel -j 0 rm -f -- ${out_log} ::: ${MASSESS_INJ[@]}
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_years \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]}
		fi
	
	done
		
    cd -

elif [ ${MODE} == "chn_years" ]; then
    echo "Selections: Processing all years and channels (mode ${MODE}, var ${VAR})..."
    
    card_dir="${LIMIT_DIR}/cards_Years_${VAR}_CombChn"
    cd ${card_dir}

    for sel in "${SELECTIONS[@]}"; do
		comb_dir="${card_dir}/${sel}_${VAR}"
		out_dir="${comb_dir}/combined_out"
		mkdir -p "${out_dir}"
    done

    # parallellize across the mass
    proc="${SIGNAL}_${VAR}_{1}"

    comb_dir_parallel="${card_dir}/{2}_${VAR}"
    out_dir_parallel="${comb_dir_parallel}/combined_out"

    in_txt="${comb_dir_parallel}/comb.${proc}.txt"
    out_log="${out_dir_parallel}/comb.${proc}.log"

    if [ ${#CATEGORIES_BOOST[@]} -ne 0 ]; then

		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_{2} \
				 ${COMM_INJ} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MHIGH[@]} ::: ${CATEGORIES_BOOST[@]}

		if [ ${#MASSES_INJ[@]} -ne 0 ]; then
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_{2} \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MHIGH_INJ[@]} ::: ${CATEGORIES_BOOST[@]}
		fi
			
    fi
    
    if [ ${#CATEGORIES_NOBOOST[@]} -ne 0 ]; then

		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_{2} \
				 ${COMM_INJ} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MASSES[@]} ::: ${CATEGORIES_NOBOOST[@]}

		if [ ${#MASSES_INJ[@]} -ne 0 ]; then
			parallel -j $((`nproc` - 1)) \
					 combine -M AsymptoticLimits ${in_txt} \
					 -n ${IDENTIFIER}_{2} \
					 ${COMM_INJ} \
					 --expectSignal ${EXPECTED_SIGNAL} \
					 --freezeParameters SignalScale \
					 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]} ::: ${CATEGORIES_NOBOOST[@]}
		fi
		
    fi
    
    cd -

elif [ ${MODE} == "all_years" ]; then

    echo "Processing all years, categories and channels (mode ${MODE}, var ${VAR})..."
    card_dir="${LIMIT_DIR}/cards_Years_${VAR}_All"
    cd ${card_dir}

    out_dir="${card_dir}/combined_out"
    mkdir -p "${out_dir}"

    # parallellize across the mass
    proc="${SIGNAL}_${VAR}_{1}"
    in_txt="${card_dir}/comb.${proc}.txt"
    out_log="${out_dir}/comb.${proc}.log"

    parallel -j 0 rm -f -- ${out_log} ::: ${MASSES[@]}
    parallel -j $((`nproc` - 1)) \
			 combine -M AsymptoticLimits ${in_txt} \
			 -n ${IDENTIFIER}_years \
			 ${COMM_INJ} \
			 --freezeParameters SignalScale \
			 -m {1} ">" ${out_log} ::: ${MASSES[@]}

	if [ ${#MASSES_INJ[@]} -ne 0 ]; then
		parallel -j 0 rm -f -- ${out_log} ::: ${MASSES_INJ[@]}
		parallel -j $((`nproc` - 1)) \
				 combine -M AsymptoticLimits ${in_txt} \
				 -n ${IDENTIFIER}_years \
				 ${COMM_INJ} \
				 --expectSignal ${EXPECTED_SIGNAL} \
				 --freezeParameters SignalScale \
				 -m {1} ">" ${out_log} ::: ${MASSES_INJ[@]}
	fi
fi
