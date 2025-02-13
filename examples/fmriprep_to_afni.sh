#!/bin/bash

function add_run_regressor () {
files=($1)
# Loop through each file
for idx in "${!files[@]}"; do
for idy in "${!files[@]}"; do

  input_file="${files[$idx]}"
  echo $input_file

  if [[ $idx -eq $idy ]] ; then
    awk 'BEGIN{OFS=","} {print $0, 1}' "$input_file" >${input_file}.bak && mv ${input_file}.bak ${input_file}
  else
    awk 'BEGIN{OFS=","} {print $0, 0}' "$input_file" >${input_file}.bak && mv ${input_file}.bak ${input_file}
  fi

done
done
}

INPUTPATH={WORKDIR}/{PIPELINE}
OUTPUTPATH={WORKDIR}/afni
EVENTNAME=years

mkdir -p $OUTPUTPATH
cd $OUTPUTPATH

echo "Using Inputs directory: $INPUTPATH"
echo "Using Outputs directory: $OUTPUTPATH"

# enable pipefail option so that results of sswarper and afni_proc report exit status after pipe
set -o pipefail

echo "Generating afni event timing 1D files...."
# bash code to store contents of bids-formatted file to fsl file format, then generate afni files
filepath_regex=$INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/*task-${EVENTNAME}*events*.tsv
event_count=$(ls $filepath_regex | wc -l)
echo "Using files for event timing..."
ls $filepath_regex

for filename in `ls $filepath_regex` ; do
    tail -n +2 $filename | while IFS=$'\t' read -r onset duration condition; do
        echo "$onset $duration 1" >> "${filename%.*}".${condition}.txt ;
        if ! grep -Fxq "$condition" _conditions;
            then echo $condition >> _conditions ;
        fi ;
    done
done

mkdir -p $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/

# generate afni 1D files
while IFS= read -r condition; do
echo "$condition"
timing_tool.py -write_as_married -fsl_timing_files $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/*${condition}.txt -write_timing $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/${condition}.1D
done < _conditions


#bash code to sub select columns from csv then merge to one file
#pip install csvkit

echo "Generating motion and nuisance regression files from fmriprep...."

# select only columns from fmriprep confounds of interest for nuisance regression - using regular expression
filepath_regex=$INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/*task-${EVENTNAME}*confounds_timeseries.tsv
confounds_count=$(ls $filepath_regex | wc -l)
echo "Using files for confounds..."
ls $filepath_regex

for filename in `ls $filepath_regex` ; do

    # extract ACompCor components (0-5) and motion derivative components for nuisance regression
    sed 's/\t/,/g' $filename | sed 's~n/a~0~g' > ${filename//.tsv/.csv}
    csvcut -n ${filename//.tsv/.csv} | grep -E '((trans|rot)_[xyz]_(derivative1|power2|derivative1_power2))$|(a_comp_cor_0[0-5])$' | cut -d":" -f2 | cut -d" " -f2 | tr '\n' ',' | sed 's/,$//' | csvcut -c $(awk -F: '{print $1}' ) ${filename//.tsv/.csv} > "${filename%.*}".nr.csv

    # extract 6 DOF head motion parameters (order: trans_x, trans_y, trans_z, rot_x, rot_y, rot_z)
    csvcut -n ${filename//.tsv/.csv} | grep -E '(trans|rot)_[xyz]$' | cut -d":" -f2 | cut -d" " -f2 | tr '\n' ',' | sed 's/,$//' | csvcut -c $(awk -F: '{print $1}' ) ${filename//.tsv/.csv} > "${filename%.*}".motion.csv
done

# add a run-id regressor to nuisance regression list
add_run_regressor "$(ls ${filepath_regex//.tsv/.nr.csv})"

# compile all nuisance regressors in one place (remove header while you are at it)
{ tail -n +2 -q ${filepath_regex//.tsv/.nr.csv} | sed 's/,/ /g' ; } > $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_nuisance_regressors.1D
echo "wrote.... nuisance_regressors.1D"

# compile all motion regressors in one place (remove header while you are at it)
{ tail -n +2 -q ${filepath_regex//.tsv/.motion.csv} | sed 's/,/ /g' ;} > $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_motion.1D

#reorder motion file as afni expects (roll pitch yaw dS dL dP) * and convert to degrees
#    AFNI units: degrees CCW, mm. Order: n (index) roll (I-S axis), pitch (R-L axis), yaw (A-P axis), dS, dL, dP
#    fmriprep units: radians, mm. Order: rot_x, rot_y, rot_z, trans_x, trans_y, trans_z
while IFS=' ' read -r rot_x rot_y rot_z trans_x trans_y trans_z
do
    # Convert angle from radians to degrees
    rot_x_deg=$(echo "$rot_x * 180 / 3.141593" | bc -l)
    rot_y_deg=$(echo "$rot_y * 180 / 3.141593" | bc -l)
    rot_z_deg=$(echo "$rot_z * 180 / 3.141593" | bc -l)
    
    # Reorder columns and output the result
    echo "$rot_z_deg $rot_x_deg $rot_y_deg $trans_z $trans_x $trans_y" >> $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_motion.1D.bak

done < $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_motion.1D

mv $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_motion.1D.bak $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_motion.1D

echo "wrote.... motion.1D"

# Some QC checks.... make sure we have the same number of events files and confounds 
if ! [[ $event_count -eq $confounds_count ]] ; then
    #problem! 
    echo "Number of Event files does not match number of confound files... Something is wrong!"
    exit 1
fi



# DO THE IMAGING STUFF NOW....

# generate func mask from fmriprep derivatives
filepath_regex=$INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/*task-${EVENTNAME}*space-MNI152NLin2009cAsym_desc-brain_mask.nii.gz
mask_count=$(ls $filepath_regex | wc -l)
echo "Using files for input mask..."
ls $filepath_regex

cmd="3dmask_tool -inputs $(ls $filepath_regex) -union -prefix $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_full_mask.nii"
echo $cmd
$cmd
echo "wrote.... full_mask.nii"


# run proc
echo "Running afni_proc.py...."
afni_proc.py                                                                                                                                                                                  \
            -subj_id                  sub-{SUBJECT}                                                                                                                                           \
            -out_dir                  $OUTPUTPATH/proc_output.fmriprep.years.{SUBJECT}                                                                                                        \
            -script                   $OUTPUTPATH/run_proc.fmriprep.years.{SUBJECT}                                                                                                           \
            -scr_overwrite                                                                                                                                                                    \
            -dsets                    $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-01_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz     \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-02_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz     \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-03_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz     \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-04_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz     \
            -blocks blur mask scale regress                                                                                                                                                   \
            -blur_size 6.0                                                                                                                                                                    \
            -tcat_remove_first_trs 22                                                                                                                                                         \
            -regress_motion_file      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_motion.1D                                                                                      \
            -regress_extra_ortvec     $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_nuisance_regressors.csv                                                                        \
            -regress_stim_times       $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/Cue.look.1D                                                                                  \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/Cue.decrease.1D                                                                              \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImagePos.look.1D                                                                             \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImagePos.decrease.1D                                                                         \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeut.look.1D                                                                            \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeut.decrease.1D                                                                        \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeg.look.1D                                                                             \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeg.decrease.1D                                                                         \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingPos.look.1D                                                                      \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingPos.decrease.1D                                                                  \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingNeg.look.1D                                                                      \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingNeg.decrease.1D                                                                  \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/iti.1D                                                                                       \
            -regress_stim_labels      cue.look                                                                                                                                                \
                                      cue.decrease                                                                                                                                            \
                                      image.pos.look                                                                                                                                          \
                                      image.pos.decrease                                                                                                                                      \
                                      image.neut.look                                                                                                                                         \
                                      image.neut.decrease                                                                                                                                     \
                                      image.neut.look                                                                                                                                         \
                                      image.neut.decrease                                                                                                                                     \
                                      image.neg.look                                                                                                                                          \
                                      image.neg.decrease                                                                                                                                      \
                                      affectrating.pos.look                                                                                                                                   \
                                      affectrating.neg.look                                                                                                                                   \
                                      iti                                                                                                                                                     \
            -regress_stim_types       AM1                                                                                                                                                     \
            -regress_basis_multi      'dmUBLOCK(-1)'                                                                                                                                          \
            -regress_local_times                                                                                                                                                              \
            -regress_opts_3dD         -jobs 8                                                                                                                                                 \
	                              -mask $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/${EVENTNAME}_full_mask.nii	                                                                      \
                                      -num_glt 1                                                                                                                                              \
                                      -gltsym 'SYM:  +image.pos.decrease +image.neut.decrease +image.neg.decrease -image.pos.look -image.neut.look -image.neg.look ' -glt_label 1 'ME_Ch_L'   \
            -regress_motion_per_run                                                                                                                                                           \
            -regress_censor_motion    0.3                                                                                                                                                     \
            -regress_censor_outliers  0.05                                                                                                                                                    \
            -regress_compute_fitts                                                                                                                                                            \
            -regress_fout             no                                                                                                                                                      \
            -regress_3dD_stop                                                                                                                                                                 \
            -regress_reml_exec                                                                                                                                                                \
            -regress_make_ideal_sum   sum_ideal.1D                                                                                                                                            \
            -regress_est_blur_errts                                                                                                                                                           \
            -regress_run_clustsim     no                                                                                                                                                      \
            -html_review_style        pythonic                                                                                                                                                \
            -bash -execute                                                                                                                                                                    \
            2>&1 | tee $OUTPUTPATH/log.afniproc.fmriprep.${EVENTNAME}.sub-{SUBJECT}


# report final exit status
exit_status=$?

if [ $exit_status -ne 0 ] ; then
echo "afni pipeline failed. See logs for details." >&2
exit 1
else
echo "Pipeline sucessed. Exiting"
fi







