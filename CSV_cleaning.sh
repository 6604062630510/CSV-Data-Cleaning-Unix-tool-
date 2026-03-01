#!/bin/bash
if [ $# -ne 1 ]; then
        echo "Error : $0 <file.csv>"
        exit 1
fi

INPUT_FILE="$1"
OUT_FILE="${INPUT_FILE%.csv}_clean.csv"

if [ ! -r "$INPUT_FILE" ]; then
        echo "Error: File '$INPUT_FILE' is not readable"
        exit 1
fi

if [ ! -s "$INPUT_FILE" ]; then
        echo "Error: File '$INPUT_FILE' is empty!"
        exit 1
fi

if [ "${INPUT_FILE##*.}" != "csv" ] && [ "${INPUT_FILE##*.}" != "CSV" ]; then
        echo "Error: File must have .csv extension!"
        exit 1
fi

check_column_counts() {
        local file="$INPUT_FILE"
        local delim=","

        if head -1 "$file" | grep -q ";"; then
                delim=";"
        elif head -1 "$file" | grep -q "|"; then
                delim="|"
        elif head -1 "$file" | grep -q $'\t'; then
                delim=$'\t'
        fi

        DELIM="$delim"
        TT_COLS=$(head -1 "$file" | awk -F"$DELIM" '{print NF}')


        MIS_LINES=$(awk -F"$DELIM" -v num="$TT_COLS" 'NF!=num {print NR, $0}' "$file")

        if [ -z "$MIS_LINES" ]; then
                return
        fi

        echo ""
        echo "=== Checking column counts (expected $TT_COLS) ==="
        echo "Some rows do not have the expected number of columns."
        echo "This may indicate missing or extra values in a row."
        echo ""
	echo "--------------------------------------------------"
	echo "Found rows with incorrect number of columns (first column is row number):"
	echo ""
	head -1 "$file" | tr "$DELIM" " "
	echo "->"
        echo "$MIS_LINES" | tr "$DELIM" " "
        echo ""

        while true; do
                echo "Choose how to handle rows with incorrect column count:"
                echo "1) Remove these rows"
                echo "2) Exit script to fix manually"
                read -p "Enter your choice (1 or 2): " ch

                if [ "$ch" = "1" ]; then
                        awk -F"$DELIM" -v num="$TT_COLS" 'NF==num' "$file" > "${OUT_FILE}.tmp"
                        mv "${OUT_FILE}.tmp" "$OUT_FILE"
			echo ""
                        echo "Rows with incorrect column count removed and saved to $OUT_FILE."
                        break
                elif [ "$ch" = "2" ]; then
                        echo "Exiting script. Please fix the file and try again."
                        exit 1
                else
                        echo "Invalid choice! Enter 1 or 2."
			echo ""
                fi
        done

        read -n1 -r -p "Press any key to continue..."
}


get_col_index() {
        local col_name="$1"
        for id in "${!COLS[@]}"; do
                if [ "${COLS[$id]}" == "$col_name" ]; then
                        echo $((id+1))
                        return
                fi
        done
        echo ""
}


show_sample_data() {
        local file="$OUT_FILE"


        echo ""
	echo ""
        echo "=== Sample data from file $file ($(cat $file | wc -l) rows, include column name)==="
        echo "---------------------------------------------------"
        head -n  10 "$file" | column -ts "$DELIM"
        echo "---------------------------------------------------"
        echo ""

        HEADER=$(head -1 "$file")
        IFS="$DELIM" read -ra COLS <<< "$HEADER"

	read -n1 -r -p "Press any key to continue..."
}	



drop_columns() {
        local file="$OUT_FILE"
        local input="$1"
        local delim="$DELIM"

        if [ "$input" = "0" ]; then
                echo "Keeping all columns (no drop)."
                cp "$file" "$OUT_FILE"
                return
        fi

        if ! echo "$input" | grep -Eq '^[0-9]+(,[0-9]+)*$'; then
                echo "! Please enter column numbers separated by commas (e.g. 1,3,5) !"
                return
        fi

        local total_cols=${#COLS[@]}
        for num in $(echo "$input" | tr ',' ' '); do
                if [ "$num" -lt 1 ] || [ "$num" -gt "$total_cols" ]; then
                        echo "! Column number $num is out of range (1โ€“$total_cols). !"
                        return
                fi
        done

        echo "You are about to drop columns: $input"
        read -p "Are you sure? (y/n): " cf
        if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then

                IFS=',' read -ra DROP_ARR <<< "$input"
                KEEP_ARR=()


                for id in "${!COLS[@]}"; do
                        col_id=$((id+1))
                        skip=false
                        for drop in "${DROP_ARR[@]}"; do
                                drop=$(echo "$drop" | xargs)
                                if [ "$col_id" -eq "$drop" ]; then
                                        skip=true
                                        break
                                fi
                        done
                        if [ "$skip" = false ]; then
                                KEEP_ARR+=("$col_id")
                        fi
                done

                CUT_COLS=$(IFS=, ; echo "${KEEP_ARR[*]}")

                cut -d"$delim" -f"$CUT_COLS" "$file" > "${OUT_FILE}.tmp"
                mv "${OUT_FILE}.tmp" "$OUT_FILE"

                echo "-- Columns dropped successfully. Updated sample --"
                head -n 5 "$OUT_FILE" | column -ts "$delim"
                echo ""


                HEADER=$(head -1 "$OUT_FILE")
                IFS="$DELIM" read -ra COLS <<< "$HEADER"
        else
                echo "! Cancelled column drop. !"
        fi
	read -n1 -r -p "Press any key to continue..."
}


select_feature_types() {
        local confirm="n"
#	echo "${#NUM_COLS[@]}"
#	echo "${NUM_COLS[@]}"

        if [ ${#NUM_COLS[@]} -eq 0 ] && [ ${#CAT_COLS[@]} -eq 0 ]; then
                echo ""
                echo "=== Specify column types for each feature ==="
                echo "Enter 1 for Numeric  |   2 for Categorical"
                echo ""

                NUM_COLS=()
                CAT_COLS=()

                for id in "${!COLS[@]}"; do
                        col="${COLS[$id]}"
                        while true
                        do
                                read -p "Column $((id+1)) - $col : " ty
                                if [ "$ty" = "1" ]; then
                                        NUM_COLS+=("$col")
                                        break
                                elif [ "$ty" = "2" ]; then
                                        CAT_COLS+=("$col")
                                        break
                                else
                                        echo "! Invalid input! Please enter 1 or 2 !"
                                fi
                        done
                done

                confirm="y"
                echo ""
                echo "-- Column types saved --"
                echo "-> Numeric columns: $(IFS=, ; echo "${NUM_COLS[*]}")"
                echo "-> Categorical columns: $(IFS=, ; echo "${CAT_COLS[*]}")"

        else
		echo ""
		echo "Current column types:"
		for id in "${!COLS[@]}"; do
			col="${COLS[$id]}"
			type="Not set"
			for n in "${NUM_COLS[@]}"; do
				if [ "$n" = "$col" ]; then
					type="Numeric"
					break
				fi
			done
			for c in "${CAT_COLS[@]}"; do
				if [ "$c" = "$col" ]; then
					type="Categorical"
					break
				fi
			done
			echo "$((id+1)) - $col : $type"
		done
		echo ""
	fi
	
	while true
	do
		echo ""
		read -p "Do you want to modify column types? (y/n): " modify
		if [ "$modify" = "y" ] || [ "$modify" = "Y" ]; then
			NUM_COLS=()
			CAT_COLS=()
			for id in "${!COLS[@]}"; do
				col="${COLS[$id]}"
				while true
				do
					echo ""
					read -p "Column $((id+1)) - $col : " ty
					if [ "$ty" = "1" ]; then
						NUM_COLS+=("$col")
						break
					elif [ "$ty" = "2" ]; then
						CAT_COLS+=("$col")
						break
					else
						echo "! Please enter 1 or 2 !"
					fi
				done
			done
			
			echo ""
			echo "-- Column types updated --"
			echo "-> Numeric columns: $(IFS=, ; echo "${NUM_COLS[*]}")"
			echo "-> Categorical columns: $(IFS=, ; echo "${CAT_COLS[*]}")"
		
		elif [ "$modify" = "n" ] || [ "$modify" = "N" ]; then
			confirm="y"
			echo "-- Keeping previous column type selection --"
			break
		else
			echo "! Please enter y or n !"
		fi
	done
        read -n1 -r -p "Press any key to continue..."        	
        
}



check_numeric_columns() {
        local file="$OUT_FILE"
        local delim="$DELIM"
        local has_error=false

        echo "=== Checking numeric columns for invalid data... ==="
        echo ""
        local header
        header=$(head -n 1 "$file")
        IFS="$delim" read -ra COLS <<< "$header"

        for col_name in "${NUM_COLS[@]}"; do
                local col_num=0

		for i in "${!COLS[@]}"; do
			if [ "${COLS[$i]}" = "$col_name" ]; then
				col_num=$((i+1))
				break
			fi
		done
                local invalid_rows=()
                while IFS= read -r line;
                do
                        invalid_rows+=("$line")
                done < <(
                        awk -F"$delim" -v col="$col_num" '
                        NR>1 && $col !~ /^ *-?[0-9]+(\.[0-9]+)? *$/ && $col !~ /^ *$/ {
                        print NR ":" $col ":" $0 }
                        ' "$file"
                        )
                if [ "${#invalid_rows[@]}" -gt 0 ]; then
                        has_error=true
                        echo "! Column $col_name has invalid numeric values !"
                        for row in "${invalid_rows[@]}"; do
                                IFS=':' read -r lineno val fullrow <<< "$row"
                                echo "  Line $lineno -> Invalid: \"$val\" | Row: $fullrow"
                        done

                        echo ""
			echo "Choose how to fix invalid values in column ( $col_name ):"
                        echo "1) Replace with mean"
                        echo "2) Replace with median"
                        echo "3) Replace with mode"
                        echo "4) Replace with custom value"
                        echo "5) Drop rows"
			echo "6) Next column"
			echo "7) Exit"

                        read -p "Enter your choice: " ch
			
			while true
			do
                        case $ch in
                                1) mean_val=$(calc_mean "$file" "$col_num" "$delim")
                                        fill_val="$mean_val"
                                        echo "-> Replacing with mean ($fill_val)"
					break
                                        ;;

                                2) median_val=$(calc_median "$file" "$col_num" "$delim")
                                        fill_val="$median_val"
                                        echo "-> Replacing with median ($fill_val)"
					break
                                        ;;
                                3) mode_val=$(calc_mode "$file" "$col_num" "$delim")
                                        fill_val="$mode_val"
                                        echo "-> Replacing with mode ($fill_val)"
					break
                                        ;;
                                4) read -p "Enter custom value: " fill_val
                                        echo "-> Replacing with custom value ($fill_val)"
					break
                                        ;;
                                5)echo "-> Dropping rows with invalid values in $col_name..."
                                        for row in "${invalid_rows[@]}"; do
                                                IFS=':' read -r lineno val fullrow <<< "$row"
                                                sed -i "${lineno}d" "$file"
                                        done
                                        continue 2
                                        ;;

				6) 
					continue 2
					;;
				7) 
					return 
					;;
                                *) echo "! Please input 1-7 !"
                                       continue 
                                        ;;
                        esac
			done

                        for row in "${invalid_rows[@]}"; do
                                IFS=':' read -r lineno val fullrow <<< "$row"
                                sed -i "${lineno}s/\(\(\([^$delim]*$delim\)\{$((col_num-1))\}\) *\)[^$delim]*/\1$fill_val/" "$file"
                        done
                        echo "-> Fixed invalid values in $col_name."
                        echo ""
                fi
        done

        if [ "$has_error" = false ]; then
                echo "-- All numeric columns are valid --"
        fi
	read -n1 -r -p "Press any key to continue..."
}

check_duplicates() {
        local file="$OUT_FILE"
        local delim="$DELIM"

        echo ""
        echo "=== Checking for duplicate rows ==="

        HEADER=$(head -1 "$file")
        DATA=$(tail -n +2 "$file")

        DUP_COUNT=$(echo "$DATA" | sort | uniq -d | wc -l)

        if [ "$DUP_COUNT" -eq 0 ]; then
                echo "No duplicate rows found."
                return
        else
                echo "Found $DUP_COUNT duplicate rows."
                echo "$DATA" | sort | uniq -d | column -ts "$delim"
        fi

        while true
        do
                read -p "Do you want to remove duplicate rows? (y/n): " CONFIRM_DUP
                if [ "$CONFIRM_DUP" = "y" ] || [ "$CONFIRM_DUP" = "Y" ]; then
                        echo "$HEADER" > "${OUT_FILE}.tmp"
                        echo "$DATA" | sort | uniq >> "${OUT_FILE}.tmp"
                        mv "${OUT_FILE}.tmp" "$OUT_FILE"
                        echo "Duplicate rows removed."
                        break
                elif [ "$CONFIRM_DUP" = "n" ] || [ "$CONFIRM_DUP" = "N" ]; then
                        echo "Duplicate removal cancelled."
                        break
                else
                        echo "! Please enter y or n !"
                fi
        done
}



calc_mean() {
        local file="$1"
        local col="$2"
        local delim="$3"
        tail -n +2 "$file" | awk -F"$delim" -v c="$col" '($c !~ /^ *$/) {
        sum += $c
        count++
        } END {
        if (count > 0)
                printf "%.3f\n", sum / count
        else
                print "NaN"
        }'
}

calc_median() {
        local file="$1"
        local col="$2"
        local delim="$3"
        tail -n +2 "$file" | awk -F"$delim" -v c="$col" '$c !~ /^ *$/ {print $c}' | sort -n | awk '{
        data[NR] = $1
        } END {
        if (NR == 0) {
                print 0; exit
        }
        mid = int((NR + 1) / 2)
        if (NR % 2 == 1)
                print data[mid]
        else
                print (data[mid] + data[mid + 1]) / 2
        }'
}


calc_mode() {
        local file="$1"
        local col="$2"
        local delim="$3"
        tail -n +2 "$file" | awk -F"$delim" -v c="$col" '$c !~ /^ *$/ {count[$c]++} END {
        max = 0
        for (v in count) {
                if (count[v] > max) {
                        max = count[v]
                        mode = v
                }
        }
        print mode
        }'
}






handle_missing_values() {
    	local file="$OUT_FILE"
    	local delim="$DELIM"
    	echo ""
    	echo "=== Handle Missing Values ==="

    	local missing_cols=()
    	local missing_counts=()
    	for id in "${!COLS[@]}"; do
        	local col="${COLS[$id]}"
        	local col_num=$((id+1))
        	local MISSING_COUNT
        	MISSING_COUNT=$(cut -d"$delim" -f"$col_num" "$file" | tail -n +2 | grep -c -E '^ *$')
        	if [ "$MISSING_COUNT" -gt 0 ]; then
            		missing_cols+=("$id")
            		missing_counts+=("$MISSING_COUNT")
        	fi
    	done

    	if [ "${#missing_cols[@]}" -eq 0 ]; then
        	echo "-- No missing values found in any column. --"
        	read -n1 -r -p "Press any key to return to menu..."
        	return
    	fi


    	echo "Columns with missing values:"
    	for i in "${!missing_cols[@]}"; do
        	idx="${missing_cols[$i]}"
        	echo "Column $((idx+1)) - ${COLS[$idx]} : ${missing_counts[$i]} missing"
    	done
    	echo ""

    	while true
	do
        	read -p "Do you want to view rows with missing values? (y/n): " vi
        	if [ "$vi" = "y" ] || [ "$vi" = "Y" ]; then
            		read -p "Enter column number to view missing rows: " COL_VIEW
            		is_missing_col=0
            		for idx in "${missing_cols[@]}"; do
                		if [ $((COL_VIEW-1)) -eq "$idx" ]; then
                    			is_missing_col=1
                    			break
                		fi
            		done
            		if [ $is_missing_col -eq 0 ]; then
                		echo "-> Column $COL_VIEW has no missing values!"
                		continue
            		fi
            		echo "Rows with missing values in column ${COLS[$((COL_VIEW-1))]}:"
            		grep -n -E "^([^$delim]*$delim){$((COL_VIEW-1))} *($delim|$)" "$file" | column -ts"$delim"
            		echo ""
        	elif [ "$vi" = "n" ] || [ "$vi" = "N" ]; then
            		break
        	else
            		echo "! Please enter only y or n !"
        	fi
    	done


    	for id in "${missing_cols[@]}"; do
        	local col="${COLS[$id]}"
        	local col_num=$((id+1))
        	local MISSING_COUNT
        	MISSING_COUNT=$(cut -d"$delim" -f"$col_num" "$file" | tail -n +2 | grep -c -E '^ *$')

        	local type="Unknown"
        	type="Unknown"
		for n in "${NUM_COLS[@]}"; do
    			if [ "$n" = "$col" ]; then
        			type="Numeric"
    			fi
		done

		for c in "${CAT_COLS[@]}"; do
    			if [ "$c" = "$col" ]; then
        			type="Categorical"
    			fi
		done	


        	echo ""
        	echo "Column $col_num - $col ($type) -> $MISSING_COUNT missing"

        	if [ "$type" = "Numeric" ]; then
			mean_val=$(calc_mean "$file" "$col_num" "$delim")
            		median_val=$(calc_median "$file" "$col_num" "$delim")
            		mode_val=$(calc_mode "$file" "$col_num" "$delim")

            		echo "1) Fill with mean ($mean_val)"
            		echo "2) Fill with median ($median_val)"
            		echo "3) Fill with mode ($mode_val)"
            		echo "4) Fill with custom value"
            		echo "5) Drop rows with missing"
		else
            		mode_val=$(calc_mode "$file" "$col_num" "$delim")
            		echo "1) Fill with mode ($mode_val)"
            		echo "2) Fill with 'Unknown'"
            		echo "3) Fill with custom value"
            		echo "4) Drop rows with missing"
        	fi

        	read -p "Enter your choice: " ch
		case $ch in
            	1)
                	if [ "$type" = "Numeric" ]; then
                    		fill_val="$mean_val"
                	else
                    		fill_val="$mode_val"
                	fi
                	;;
            	2)
                	if [ "$type" = "Numeric" ]; then
                    		fill_val="$median_val"
                	else
                    		fill_val="Unknown"
                	fi
                	;;
            	3)
                	read -p "Enter custom value to fill: " fill_val
                	;;

		4) 
			if [ "$type" = "Numeric" ]; then 
				read -p "Enter custom value to fill: " fill_val 
				echo "-> Filling $col with custom value ($fill_val)" 
			else 
				echo "-> Dropping rows with missing in $col..." 
				sed -E "/^(([^$delim]*$delim){$((col_num-1))}) *\$/d" "$file" > "${OUT_FILE}.tmp" 
				mv "${OUT_FILE}.tmp" "$OUT_FILE" 
				break 
			fi 
			;; 
		
		5) 
			if [ "$type" = "Numeric" ]; then 
				echo "-> Dropping rows with missing in $col..." 
				sed -E "/^(([^$delim]*$delim){$((col_num-1))}) *\$/d" "$file" > "${OUT_FILE}.tmp" 
				mv "${OUT_FILE}.tmp" "$OUT_FILE" 
				break 
			else 
				echo "Invalid choice!" 
				continue 
			fi 
			;;

            	*)
                	echo "Invalid choice!"
                	continue
                	;;
        	esac

        	sed -E "s/^(([^$delim]*$delim){$((col_num-1))}) *($delim|$)/\1$fill_val\3/" "$file" > "${OUT_FILE}.tmp"
        	mv "${OUT_FILE}.tmp" "$OUT_FILE"
        	echo "-> Missing values in $col replaced with '$fill_val'."
    	done

    	echo ""
    	echo "-- Missing values handled successfully. --"
    	read -n1 -r -p "Press any key to continue..."
}








calc_std() {
    	local file="$1"
    	local col="$2"
    	local delim="$3"

    	awk -F"$delim" -v c="$col" '
    	NR > 1 && $c ~ /^ *-?[0-9]+(\.[0-9]+)? *$/ {
        	sum += $c
        	sumsq += ($c) * ($c)
        	n++
    	}
    	END {
        	if (n > 1) {
            		var = (sumsq - (sum*sum)/n) / (n-1)
            		printf "%.6f\n", sqrt(var)
        	} else {
            		print 0
        	}
    	}' "$file"
}











handle_outliers() {
    	local file="$OUT_FILE"
    	local delim="$DELIM"

    	echo ""
    	echo "=== Handle Outliers (Numeric only) ==="
    	echo ""

    	if [ ${#NUM_COLS[@]} -eq 0 ]; then
        	echo "! No numeric columns found !"
        	read -n1 -r -p "Press any key to return to menu..."
        	return
    	fi

    	echo "Available numeric columns:"
    	for i in "${!NUM_COLS[@]}"; do
        	echo "$((i+1))) ${NUM_COLS[$i]}"
    	done

    	read -p "Select a column number: " col_choice
    	local col_name="${NUM_COLS[$((col_choice-1))]}"
    	local col_num
    	col_num=$(get_col_index "$col_name")

    	if [ -z "$col_num" ]; then
        	echo "Invalid column selection."
        	read -n1 -r -p "Press any key to return..."
        	return
    	fi

	while true
	do
    		echo ""
    		echo "Choose outlier detection method:"
    		echo "1) IQR method"
    		echo "2) Z-score method"
    		read -p "Enter your choice (1 or 2): " met_ch

    		if [ "$met_ch" = "1" ] || [ "$met_ch" = "2" ]; then
        		break
    		else
        		echo "Invalid choice! Please enter 1 or 2."
    		fi
	done

	case $met_ch in
    		1)
			echo ""
        		echo "-> Detecting outliers using IQR method..."
        		vals=($(awk -F"$delim" -v c=$col_num 'NR>1 && $c !~ /^ *$/ {print $c}' "$file" | sort -n))
        		n=${#vals[@]}
        		if [ $n -lt 4 ]; then
            			echo "Not enough data to compute IQR."
            			return
        		fi

        		q1_id=$(awk -v n=$n 'BEGIN{print int(0.25*(n-1))+1}')
        		q3_id=$(awk -v n=$n 'BEGIN{print int(0.75*(n-1))+1}')
        		Q1=${vals[$((q1_id-1))]}
        		Q3=${vals[$((q3_id-1))]}
        		IQR=$(awk -v q1=$Q1 -v q3=$Q3 'BEGIN{print q3-q1}')
        		LOWER=$(awk -v q1=$Q1 -v iqr=$IQR 'BEGIN{print q1 - 1.5*iqr}')
        		UPPER=$(awk -v q3=$Q3 -v iqr=$IQR 'BEGIN{print q3 + 1.5*iqr}')
        		echo "Q1=$Q1, Q3=$Q3, IQR=$IQR"
        		echo "Acceptable range: [$LOWER, $UPPER]"
        		;;
    		2)
        		echo ""
        		echo "-> Detecting outliers using Z-score method..."
        		mean_val=$(calc_mean "$file" "$col_num" "$delim")
        		std_val=$(calc_std "$file" "$col_num" "$delim")
        		echo "Mean=$mean_val, Std=$std_val"
      	  		;;
	esac

    	echo ""
    	if confirm_input "Do you want to remove outliers"; then
    		echo "-> Removing outliers in column $col_name..."
    		if [ "$met_ch" -eq 1 ]; then
        		awk -F"$delim" -v c=$col_num -v low="$LOWER" -v up="$UPPER" -v OFS="$delim" \
            		'NR==1 || ($c >= low && $c <= up)' "$file" > "${OUT_FILE}.tmp"
    		else
        		awk -F"$delim" -v c=$col_num -v mean="$mean_val" -v std="$std_val" -v OFS="$delim" \
            		'NR==1 || (std>0 && (($c-mean)/std <= 3 && ($c-mean)/std >= -3))' "$file" > "${OUT_FILE}.tmp"
    		fi
    		mv "${OUT_FILE}.tmp" "$OUT_FILE"
    		echo "-- Outliers removed successfully --"
	else
    		echo "Outlier removal cancelled"
	fi


	read -n1 -r -p "Press any key to return to menu..."
}







handle_normalize() {
    	local file="$OUT_FILE"
    	local delim="$DELIM"

    	echo ""
    	echo "=== Normalize / Scale Numeric Features ==="
    	echo ""

    	if [ ${#NUM_COLS[@]} -eq 0 ]; then
        	echo "! No numeric columns found !"
        	read -n1 -r -p "Press any key to return to menu..."
        	return
    	fi

    	echo "Available numeric columns:"
    	for i in "${!NUM_COLS[@]}"; do
        	echo "$((i+1))) ${NUM_COLS[$i]}"
    	done

    	local col_ch
    	
	
	while true
  	do
        	read -p "Select a column number to normalize/scale: " col_ch
        	if [[ "$col_ch" =~ ^[0-9]+$ ]] && [ "$col_ch" -ge 1 ] && [ "$col_ch" -le "${#NUM_COLS[@]}" ]; then
            		break
        	else
            		echo "! Please enter a valid number !"
        	fi
    	done

    	local col_name="${NUM_COLS[$((col_ch-1))]}"
    	local col_num
    	col_num=$(get_col_index "$col_name")
    	
	if [ -z "$col_num" ]; then
        	echo "Invalid column index."
        	return
    	fi


    	echo ""
    	echo "Choose normalization/scaling method: "

    	echo "1) Min-Max scaling (0-1)"
    	echo "2) Z-score standardization"
    	local met_ch
	
	while true
	do
    		read -p "Enter your choice: " met_ch
    		if [ "$met_ch" = "1" ] || [ "$met_ch" = "2" ]; then
        		break
    		else
        		echo "Invalid choice! Enter 1 or 2."
    		fi
	done

    	col_val=($(tail -n +2 "$file" | cut -d"$delim" -f"$col_num" | grep -v -E '^ *$'))

    	local min_val max_val mean_val std_val
    	if [ "$met_ch" == "1" ]; then
        	min_val=$(printf "%s\n" "${col_val[@]}" | sort -n | head -n1)
        	max_val=$(printf "%s\n" "${col_val[@]}" | sort -n | tail -n1)
   	else
        	mean_val=$(calc_mean "$file" "$col_num" "$delim")
        	std_val=$(calc_std "$file" "$col_num" "$delim")
    	fi

    	head -n1 "$file" > "${OUT_FILE}.tmp"

    	echo ""
	echo "Normalizing/scaling column '$col_name'..."
	echo "This may take a few seconds, please wait..."

	while IFS="$delim" read -r line; do
    		val=$(echo "$line" | cut -d"$delim" -f"$col_num")

    		if echo "$val" | grep -q -E '^ *$'; then
        		new_line="$line"
    		else
        		if [ "$met_ch" = "1" ]; then
            			norm_val=$(awk -v x="$val" -v min="$min_val" -v max="$max_val" \
                		'BEGIN{printf "%.6f", (max-min==0)?0:(x-min)/(max-min)}')
        		else
            			norm_val=$(awk -v x="$val" -v mean="$mean_val" -v std="$std_val" \
                		'BEGIN{printf "%.6f", (std==0)?0:(x-mean)/std}')
        		fi
        		new_line=$(echo "$line" | sed -E "s/^(([^$delim]*$delim){$((col_num-1))})[^$delim]+/\1$norm_val/")
    		fi
    		echo "$new_line" >> "${OUT_FILE}.tmp"
	done < <(tail -n +2 "$file")


    	mv "${OUT_FILE}.tmp" "$OUT_FILE"
    	echo "-- Column '$col_name' normalized/scaled successfully --"
    	read -n1 -r -p "Press any key to return to menu..."
}





confirm_input() {
    	local prompt="$1"
    	local ans
    	while true; do
        	read -p "$prompt (y/n): " ans
        	if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
            		return 0
        	elif [ "$ans" = "n" ] || [ "$ans" = "N" ]; then
            		return 1
        	else
            		echo "! Invalid input. Please enter only y or n !"
        	fi
    	done
}







check_data_validity() {
    	local file="$OUT_FILE"
    	local delim="$DELIM"

    	echo ""
    	echo "=== Check Data Validity / Accuracy ==="
    	echo ""
    	if [ ${#NUM_COLS[@]} -gt 0 ]; then
        	echo ""
        	echo "-> Checking numeric columns..."
        	for col_name in "${NUM_COLS[@]}"; do
            		col_num=$(get_col_index "$col_name")
            		echo ""
            		echo "Column: $col_name"

			min_val=$(awk -F"$delim" -v c=$col_num 'NR>1 && $c !~ /^ *$/ {if(min=="" || $c<min) min=$c} END{print min}' "$file")
			max_val=$(awk -F"$delim" -v c=$col_num 'NR>1 && $c !~ /^ *$/ {if(max=="" || $c>max) max=$c} END{print max}' "$file")
            		echo "Min: $min_val, Max: $max_val"

			if confirm_input "Do you want to filter values outside a specific range?"; then
    				read -p "Enter minimum allowed value: " min_allow
    				read -p "Enter maximum allowed value: " max_allow
    				awk -F"$delim" -v c=$col_num -v min=$min_allow -v max=$max_allow -v OFS="$delim" \
        			'NR==1 || ($c !~ /^ *$/ && $c >= min && $c <= max)' "$file" > "${OUT_FILE}.tmp"
    				mv "${OUT_FILE}.tmp" "$OUT_FILE"
    				echo "-> Rows outside [$min_allow, $max_allow] removed."
			fi

        	done
    	fi


    	if [ ${#CAT_COLS[@]} -gt 0 ]; then
		echo ""
		echo "-----------------------------------------"
		echo ""
        	echo "-> Checking categorical columns..."
        	for col_name in "${CAT_COLS[@]}"; do
            		col_num=$(get_col_index "$col_name")
            		echo ""
            		echo "Column: $col_name"
            		cut -d"$delim" -f"$col_num" "$file" | tail -n +2 | sort | uniq -c | sort -nr | column -t

			if confirm_input "Do you want to replace invalid/mistyped values in $col_name?"; then
    				while true
				do
        				while true
					do
            					read -p "Enter value to replace (current): " old_val
            					exists=$(awk -F"$delim" -v c=$col_num -v val="$old_val" \
						       	'NR>1 && $c==val {found=1} END{print found+0}' "$file")
            					if [ "$exists" -eq 1 ]; then
                					break
            					else
                					echo "! Value '$old_val' not found in column $col_name. Please enter a valid existing value."
            					fi
        				done

        				read -p "Enter new value: " new_val
        				sed -i "s/$old_val/$new_val/g" "$file"
        				echo "-> Replaced '$old_val' with '$new_val' in column $col_name"

        				if ! confirm_input "Replace another value in $col_name?"; then
            					break
        				fi
    				done
			fi
 
		done
    	fi



    	echo ""
    	read -n1 -r -p "Press any key to return to menu..."

}



manual_edit_data() {
    	local file="$OUT_FILE"
    	local delim="$DELIM"

    	echo ""
    	echo "=== Manual Data Editing ==="
    	echo ""

    	echo "Displaying data (header included) ..."
    	echo ""
    	cat -n "$file" | column -ts "$DELIM" | less
    	echo ""

    	while confirm_input "Do you want to edit a value?"
	do
        	read -p "Enter the row number to edit (or 'g' to replace a value in all rows of a column): " row_input
        	read -p "Enter the column number to edit: " col_num

        	if [ "$row_input" = "g" ]; then

	        	while true
			do
                		read -p "Enter value to search for in column $col_num: " old_val
                		exists=$(awk -F"$delim" -v c=$col_num -v val="$old_val" 'NR>1 && $c==val {found=1} END{print found+0}' "$file")
                		if [ "$exists" -eq 1 ]; then
                    			break
                		else
                    			echo "! Value '$old_val' not found in column $col_num. Please enter a valid existing value."
                		fi
            		done

            		read -p "Enter new value to replace with: " new_val

            		if confirm_input "Replace ALL occurrences of '$old_val' with '$new_val' in column $col_num?"; then
                		sed -E -i "s/^(([^$delim]*$delim){$((col_num-1))})${old_val}/\1$new_val/" "$file"
                		echo "-- All occurrences in column $col_num replaced --"
				echo ""
            		else
                		echo "! Skipped !"
            		fi
            		continue
        	fi

        	row_num="$row_input"
        	old_val=$(awk -F"$delim" -v r="$row_num" -v c="$col_num" 'NR==r {print $c}' "$file")
        	echo "Current value at row $row_num, column $col_num: '$old_val'"

        	read -p "Enter new value: " new_val

        	if confirm_input "Are you sure you want to replace '$old_val' with '$new_val'?"; then
            		sed -E -i "${row_num}s/^(([^$delim]*$delim){$((col_num-1))})[^$delim]*/\1$new_val/" "$file"
            		echo "-- Row $row_num, Column $col_num updated to '$new_val' --"
        	else
            		echo "! Skipped !"
        	fi

        	echo ""
    	done

    	echo "-- Manual editing finished --"
    	read -n1 -r -p "Press any key to continue..."
}









main_menu() {
    	while true
	do
        	echo ""
        	echo "=============================="
        	echo "      Data Cleaning Menu      "
        	echo "=============================="
        	echo "File: $OUT_FILE ($(cat $OUT_FILE | wc -l) rows, include column name)"
        	echo ""
        	echo "1) Show sample data"
		echo "2) View full data (press q to exit)"
        	echo "3) View / modify column types (Numeric / Categorical)"
        	echo "4) Check numeric columns"
        	echo "5) Handle missing values (Numeric / Categorical)"
        	echo "6) Handle outliers (Numeric only)"
        	echo "7) Normalize / scale numeric features"
        	echo "8) Check data validity / accuracy"
        	echo "9) Remove duplicate rows"
        	echo "10) Manual edit data"
        	echo "11) Drop column"
        	echo "12) Exit"
        	echo "=============================="

        	read -p "Choose an option: " ch
        	case "$ch" in
            		1)
                		head -n 10 "$OUT_FILE" | column -ts "$DELIM"
                		;;
            		2)
                		cat -n "$OUT_FILE" | column -ts "$DELIM" | less
                		;;
            		3)
               			 select_feature_types
                		;;
           		4)
				check_numeric_columns
				;;
            		5)
                		handle_missing_values
                		;;
            		6)
                		handle_outliers
                		;;
            		7)
                		handle_normalize
                		;;
            		8)
                		check_data_validity
                		;;
            		9)
                		check_duplicates
                		;;
	    		10)
       				manual_edit_data
       	 			;;

            		11)
                		read -p "Enter column numbers to drop (comma separated) or 0 to keep all: " DROP_INPUT
                		drop_columns "$DROP_INPUT"
                		;;
            		12)
              			echo "Exiting menu..."
                		break
                		;;
            		*)
                		echo "! Please enter a number between 1-12 !"
                		;;
        	esac
    	done
}

check_column_counts
show_sample_data
echo ""
if confirm_input "Do you want to drop some columns?"; then
    read -p "Enter column numbers to drop (comma separated) or 0 to keep all: " DROP_INPUT
    drop_columns "$DROP_INPUT"
fi


select_feature_types
main_menu