#!/bin/bash

# --------------------------------------------------
#            START RUN SCRIPT: YEARS
# --------------------------------------------------

# USER INPUTS!!
INPUTPATH={WORKDIR}/{PIPELINE}/sub-{SUBJECT}/ses-{SESSION}/
OUTPUTPATH={WORKDIR}/afni
EVENTNAME=years
TRIMFRAMES=22
TR=0.460
EVENTSPATH={WORKDIR}/{PIPELINE}/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}

mkdir -p $OUTPUTPATH
mkdir -p $EVENTSPATH
cd $OUTPUTPATH

echo "Running Pipleine for fMRI acquistion type: $EVENTNAME"
echo "Using Inputs directory: $INPUTPATH"
echo "Using Outputs directory: $OUTPUTPATH"

# enable pipefail option so that results of sswarper and afni_proc report exit status after pipe
set -o pipefail

echo "Generating afni event timing 1D files...."
touch _conditions
# bash code to store contents of bids-formatted file to fsl file format, then generate afni files
filepath_regex=$INPUTPATH/func/*task-${EVENTNAME}*events*.tsv
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

# apply timing offset to match afni-proc trimming
OFFSET=$(echo "$TR * $TRIMFRAMES" | bc -l)
echo "Including timing offset: $OFFSET"

# generate afni 1D files
echo "Using conditions: "
while IFS= read -r condition; do
echo "  $condition"
timing_tool.py -write_as_married -add_offset -$OFFSET -fsl_timing_files $INPUTPATH/func/*${EVENTNAME}*${condition}.txt -write_timing $EVENTSPATH/${condition}.1D
done < _conditions

# delete intermediate files
rm _conditions
rm $INPUTPATH/func/*${EVENTNAME}*${condition}.txt


# DO THE IMAGING STUFF NOW....

# deoblique all input data
shopt -s extglob
echo "Creating deoblique datasets..."
for i in `ls $INPUTPATH/*@(anat|func)*/*.nii.gz` ; do
  cmd="3dWarp -deoblique -prefix ${i//.nii.gz/.bak.nii.gz} $i";
  echo $cmd; $cmd ;
  mv ${i//.nii.gz/.bak.nii.gz} $i
done

echo "Running SSwarper...."
@SSwarper                                                                                                                   \
        -input  $INPUTPATH/anat/sub-{SUBJECT}_ses-{SESSION}_acq-mpr08_run-01_T1w.nii.gz                                     \
        -base   MNI152_2009_template_SSW.nii.gz                                                                             \
        -subid  sub-{SUBJECT}                                                                                               \
        -odir   ssw1.{SUBJECT}/                                                                                             \
        -verb                                                                                                               \
        2>&1 | tee log.sswarper.sub-{SUBJECT}

# REQUIRED SLEEP!! Flywheel apptainer run seems to not show new files immediately after sswarper...this solves it
echo "Pause... Making sure all files are written and accessible..."
sleep 5m

# check all is good....
echo "Double checking output..."
cmd="3dnvals -all ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.nii"
echo $cmd
$cmd

echo "Running afni_proc.py...."
afni_proc.py                                                                                                               \
            -subj_id                  sub-{SUBJECT}                                                                        \
            -out_dir                  proc_output.years.{SUBJECT}                                                          \
            -script                   run_proc.years.{SUBJECT}                                                             \
            -dsets                    $INPUTPATH/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-01_bold.nii.gz     \
                                      $INPUTPATH/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-02_bold.nii.gz     \
                                      $INPUTPATH/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-03_bold.nii.gz     \
                                      $INPUTPATH/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-04_bold.nii.gz     \
            -copy_anat                ssw1.{SUBJECT}/anatSS.sub-{SUBJECT}.nii                                              \
            -anat_has_skull           no                                                                                   \
            -anat_follower            anat_w_skull anat                                                                    \
                                      ssw1.{SUBJECT}/anatU.sub-{SUBJECT}.nii                                               \
            -blocks                   tshift align tlrc volreg mask blur                                                   \
                                      scale regress                                                                        \
            -radial_correlate_blocks  tcat volreg regress                                                                  \
            -tcat_remove_first_trs    22                                                                                   \
            -tshift_opts_ts           -tpattern alt+z2                                                                     \
            -align_unifize_epi        local                                                                                \
            -align_opts_aea           -giant_move -cost lpc+ZZ                                                             \
                                      -check_flip                                                                          \
            -tlrc_base                MNI152_2009_template_SSW.nii.gz                                                      \
            -tlrc_NL_warp                                                                                                  \
            -tlrc_NL_warped_dsets     ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.nii                                              \
                                      ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.aff12.1D                                         \
                                      ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}_WARP.nii                                         \
            -volreg_align_to          MIN_OUTLIER                                                                          \
            -volreg_align_e2a                                                                                              \
            -volreg_tlrc_warp                                                                                              \
            -volreg_warp_dxyz         3.0                                                                                  \
            -volreg_compute_tsnr      yes                                                                                  \
            -mask_epi_anat            yes                                                                                  \
            -blur_size                6                                                                                    \
            -blur_in_mask             yes                                                                                  \
            -regress_stim_times       $EVENTSPATH/Cue.look.1D                                            \
                                      $EVENTSPATH/Cue.decrease.1D                                        \
                                      $EVENTSPATH/ImagePos.look.1D                                       \
                                      $EVENTSPATH/ImagePos.decrease.1D                                   \
                                      $EVENTSPATH/ImageNeut.look.1D                                      \
                                      $EVENTSPATH/ImageNeg.look.1D                                       \
                                      $EVENTSPATH/ImageNeg.decrease.1D                                   \
                                      $EVENTSPATH/AffectratingPos.look.1D                                \
                                      $EVENTSPATH/AffectratingPos.decrease.1D                            \
                                      $EVENTSPATH/AffectratingNeg.look.1D                                \
                                      $EVENTSPATH/AffectratingNeg.decrease.1D                            \
                                      $EVENTSPATH/iti.1D                                                 \
            -regress_stim_labels      cue.look                                                                              \
                                      cue.decrease                                                                          \
                                      image.pos.look                                                                        \
                                      image.pos.decrease                                                                    \
                                      image.neut.look                                                                       \
                                      image.neg.look                                                                        \
                                      image.neg.decrease                                                                    \
                                      affectrating.pos.look                                                                 \
                                      affectrating.pos.decrease                                                             \
                                      affectrating.neg.look                                                                 \
                                      affectrating.neg.decrease                                                             \
                                      iti                                                                                   \
            -regress_stim_types       AM1                                                                                   \
            -regress_basis_multi      'dmUBLOCK(-1)'                                                                        \
            -regress_local_times                                                                                            \
            -regress_opts_reml        -GOFORIT 1                                                                            \
            -regress_opts_3dD         -jobs 8                                                                               \
                                      -allzero_OK                                                                           \
                                      -GOFORIT 1                                                                            \
                                      -num_glt 1                                                                            \
                                      -gltsym 'SYM:  +image.pos.decrease +image.neg.decrease -image.pos.look -image.neg.look' \
                                      -glt_label 1 'ME_Ch_L'                                                                \
            -regress_motion_per_run                                                                                         \
            -regress_censor_motion    0.3                                                                                   \
            -regress_censor_outliers  0.05                                                                                  \
            -regress_compute_fitts                                                                                          \
            -regress_fout             no                                                                                    \
            -regress_3dD_stop                                                                                               \
            -regress_reml_exec                                                                                              \
            -regress_make_ideal_sum   sum_ideal.1D                                                                          \
            -regress_est_blur_errts                                                                                         \
            -regress_run_clustsim     no                                                                                    \
            -html_review_style        pythonic                                                                              \
            -bash -execute                                                                                                  \
            2>&1 | tee log.afniproc.years.sub-{SUBJECT}

# report final exit status
exit_status=$?

if [ $exit_status -ne 0 ] ; then
echo "afni pipeline failed. See logs for details." >&2
exit 1
else
echo "Pipeline succeeded. Proceeding..."
fi


# --------------------------------------------------
#            START RUN SCRIPT: MID
# --------------------------------------------------

#USER INPUTS!!
INPUTPATH={WORKDIR}/{PIPELINE}/sub-{SUBJECT}/ses-{SESSION}/
OUTPUTPATH={WORKDIR}/afni
EVENTNAME=mid
TRIMFRAMES=0
TR=2.6
EVENTSPATH={WORKDIR}/{PIPELINE}/sub-{SUBJECT}/ses-{SESSION}/func/events/${EVENTNAME}

mkdir -p $OUTPUTPATH
mkdir -p $EVENTSPATH
cd $OUTPUTPATH

echo "Running Pipleine for fMRI acquistion type: $EVENTNAME"
echo "Using Inputs directory: $INPUTPATH"
echo "Using Outputs directory: $OUTPUTPATH"


echo "Generating afni event timing 1D files...."
touch _conditions
# bash code to store contents of bids-formatted file to fsl file format, then generate afni files
filepath_regex=$INPUTPATH/func/*task-${EVENTNAME}*events*.tsv
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


# apply timing offset to match afni-proc trimming
OFFSET=$(echo "$TR * $TRIMFRAMES" | bc -l)
echo "Including timing offset: $OFFSET"

# generate afni 1D files
echo "Using conditions: "
while IFS= read -r condition; do
echo "  $condition"
timing_tool.py -write_as_married -add_offset -$OFFSET -fsl_timing_files $INPUTPATH/func/*${EVENTNAME}*${condition}.txt -write_timing $EVENTSPATH/${condition}.1D
done < _conditions

# delete intermediate files
rm _conditions
rm $INPUTPATH/func/*${EVENTNAME}*${condition}.txt


# DO THE IMAGING STUFF NOW....

echo "Running afni_proc.py...."
afni_proc.py                                                                                                                \
            -subj_id                  sub-{SUBJECT}                                                                         \
            -out_dir                  proc_output.mid.{SUBJECT}                                                             \
            -script                   run_proc.mid.{SUBJECT}                                                                \
            -dsets                    $INPUTPATH/func/sub-{SUBJECT}_ses-{SESSION}_task-mid_dir-ap_run-01_bold.nii.gz        \
            -copy_anat                ssw1.{SUBJECT}/anatSS.sub-{SUBJECT}.nii                                               \
            -anat_has_skull           no                                                                                    \
            -anat_follower            anat_w_skull anat                                                                     \
                                      ssw1.{SUBJECT}/anatU.sub-{SUBJECT}.nii                                                \
            -blocks                   tshift align tlrc volreg mask blur                                                    \
                                      scale regress                                                                         \
            -radial_correlate_blocks  tcat volreg regress                                                                   \
            -tcat_remove_first_trs    0                                                                                     \
            -tshift_opts_ts           -tpattern alt+z2                                                                      \
            -align_unifize_epi        local                                                                                 \
            -align_opts_aea           -giant_move -cost lpc+ZZ                                                              \
                                      -check_flip                                                                           \
            -tlrc_base                MNI152_2009_template_SSW.nii.gz                                                       \
            -tlrc_NL_warp                                                                                                   \
            -tlrc_NL_warped_dsets     ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.nii                                               \
                                      ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.aff12.1D                                          \
                                      ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}_WARP.nii                                          \
            -volreg_align_to          MIN_OUTLIER                                                                           \
            -volreg_align_e2a                                                                                               \
            -volreg_tlrc_warp                                                                                               \
            -volreg_warp_dxyz         3.0                                                                                   \
            -volreg_compute_tsnr      yes                                                                                   \
            -mask_epi_anat            yes                                                                                   \
            -blur_size                6                                                                                     \
            -blur_in_mask             yes                                                                                   \
            -regress_stim_times       $EVENTSPATH/instructions.1D                                        \
                                      $EVENTSPATH/E.cue.1D                                               \
                                      $EVENTSPATH/E.target.1D                                            \
                                      $EVENTSPATH/E.failure.1D                                           \
                                      $EVENTSPATH/P.cue.1D                                               \
                                      $EVENTSPATH/P.target.1D                                            \
                                      $EVENTSPATH/P.failure.1D                                           \
                                      $EVENTSPATH/iti.1D                                                 \
            -regress_stim_labels      instr E.cue E.target E.failure P.cue P.target P.failure iti                           \
            -regress_stim_types       AM1                                                                                   \
            -regress_basis_multi      'dmUBLOCK(-1)'                                                                        \
            -regress_local_times                                                                                            \
            -regress_opts_reml        -GOFORIT 1                                                                            \
            -regress_opts_3dD         -jobs 8                                                                               \
	                              -allzero_OK                                                                           \
	    	                      -GOFORIT 1                                                                            \
                                      -num_glt 1                                                                            \
                                      -gltsym 'SYM: 0.5*E.target +0.5*P.target '                                            \
                                      -glt_label 1 posControl                                                               \
            -regress_motion_per_run                                                                                         \
            -regress_censor_motion    0.3                                                                                   \
            -regress_censor_outliers  0.05                                                                                  \
            -regress_compute_fitts                                                                                          \
            -regress_fout             no                                                                                    \
            -regress_3dD_stop                                                                                               \
            -regress_reml_exec                                                                                              \
            -regress_make_ideal_sum   sum_ideal.1D                                                                          \
            -regress_est_blur_errts                                                                                         \
            -regress_run_clustsim     no                                                                                    \
            -html_review_style        pythonic                                                                              \
            -bash -execute                                                                                                  \
            2>&1 | tee log.afniproc.mid.sub-{SUBJECT} 


# report final exit status
exit_status=$?

if [ $exit_status -ne 0 ] ; then
echo "afni pipeline failed. See logs for details." >&2
exit 1
else
echo "Pipeline succeeded. Exiting"
exit 0
fi
