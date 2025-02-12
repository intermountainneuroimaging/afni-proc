#!/bin/bash

INPUTPATH={WORKDIR}/{PIPELINE}/
OUTPUTPATH={WORKDIR}/afni/
EVENTNAME=years

mkdir -p $OUTPUTPATH

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



# DO THE IMAGING STUFF NOW....

# deoblique all input data
shopt -s extglob
echo "Creating deoblique datasets..."
for i in `ls $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/*@(anat|func)*/*.nii.gz` ; do
  cmd="3dWarp -deoblique -prefix $i $i";
  echo $cmd; $cmd ;
done

echo "Running SSwarper...."
@SSwarper                                                                                                                                               \
        -input  $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/anat/sub-{SUBJECT}_ses-{SESSION}_acq-mpr08_run-01_T1w.nii.gz                                     \
        -base   MNI152_2009_template_SSW.nii.gz                                                                                                         \
        -subid  sub-{SUBJECT}                                                                                                                           \
        -odir   $OUTPUTPATH/ssw1.{SUBJECT}/                                                                                                             \
        -verb                                                                                                                                           \
        2>&1 | tee $OUTPUTPATH/log.sswarper.sub-{SUBJECT}


echo "Running afni_proc.py...."
afni_proc.py                                                                                                                                            \
            -subj_id                  sub-{SUBJECT}                                                                                                     \
            -out_dir                  $OUTPUTPATH/proc_output.years.{SUBJECT}                                                                           \
            -script                   $OUTPUTPATH/run_proc.years.{SUBJECT}                                                                              \
            -dsets                    $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-01_bold.nii.gz      \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-02_bold.nii.gz      \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-03_bold.nii.gz      \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-years_dir-ap_run-04_bold.nii.gz      \
            -copy_anat                {WORKDIR}/afni/ssw1.{SUBJECT}/anatSS.sub-{SUBJECT}.nii                                                            \
            -anat_has_skull           no                                                                                                                \
            -anat_follower            anat_w_skull anat                                                                                                 \
                                      $OUTPUTPATH/ssw1.{SUBJECT}/anatU.sub-{SUBJECT}.nii                                                                \
            -blocks                   tshift align tlrc volreg mask blur                                                                                \
                                      scale regress                                                                                                     \
            -radial_correlate_blocks  tcat volreg regress                                                                                               \
            -tcat_remove_first_trs    22                                                                                                                \
            -tshift_opts_ts           -tpattern alt+z2                                                                                                  \
            -align_unifize_epi        local                                                                                                             \
            -align_opts_aea           -giant_move -cost lpc+ZZ                                                                                          \
                                      -check_flip                                                                                                       \
            -tlrc_base                MNI152_2009_template_SSW.nii.gz                                                                                   \
            -tlrc_NL_warp                                                                                                                               \
            -tlrc_NL_warped_dsets     $OUTPUTPATH/ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.nii                                                               \
                                      $OUTPUTPATH/ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}.aff12.1D                                                          \
                                      $OUTPUTPATH/ssw1.{SUBJECT}/anatQQ.sub-{SUBJECT}_WARP.nii                                                          \
            -volreg_align_to          MIN_OUTLIER                                                                                                       \
            -volreg_align_e2a                                                                                                                           \
            -volreg_tlrc_warp                                                                                                                           \
            -volreg_warp_dxyz         3.0                                                                                                               \
            -volreg_compute_tsnr      yes                                                                                                               \
            -mask_epi_anat            yes                                                                                                               \
            -blur_size                6                                                                                                                 \
            -blur_in_mask             yes                                                                                                               \
            -regress_stim_times       $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/Cue.look.1D                                            \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/Cue.decrease.1D                                        \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImagePos.look.1D                                       \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImagePos.decrease.1D                                   \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeut.look.1D                                      \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeut.decrease.1D                                  \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeg.look.1D                                       \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/ImageNeg.decrease.1D                                   \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingPos.look.1D                                \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingPos.decrease.1D                            \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingNeg.look.1D                                \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/AffectratingNeg.decrease.1D                            \
                                      $INPUTPATH/sub-{SUBJECT}/ses-{SESSION}/events/${EVENTNAME}/iti.1D                                                 \
            -regress_stim_labels      cue.look                                                                                                          \
                                      cue.decrease                                                                                                      \
                                      image.pos.look                                                                                                    \
                                      image.pos.decrease                                                                                                \
                                      image.neut.look                                                                                                   \
                                      image.neut.decrease                                                                                               \
                                      image.neut.look                                                                                                   \
                                      image.neut.decrease                                                                                               \
                                      image.neg.look                                                                                                    \
                                      image.neg.decrease                                                                                                \
                                      affectrating.pos.look                                                                                             \
                                      affectrating.neg.look                                                                                             \
                                      iti                                                                                                               \
            -regress_stim_types       AM1                                                                                                               \
            -regress_basis_multi      'dmUBLOCK(-1)'                                                                                                    \
            -regress_local_times                                                                                                                        \
            -regress_opts_3dD         -jobs 8                                                                                                           \
                                      -num_glt 1                                                                                                        \
                                      -gltsym 'SYM:  +image.pos.decrease +image.neut.decrease +image.neg.decrease -image.pos.look -image.neut.look -image.neg.look ' -glt_label 1 'ME_Ch_L'   \
            -regress_motion_per_run                                                                                                                     \
            -regress_censor_motion    0.3                                                                                                               \
            -regress_censor_outliers  0.05                                                                                                              \
            -regress_compute_fitts                                                                                                                      \
            -regress_fout             no                                                                                                                \
            -regress_3dD_stop                                                                                                                           \
            -regress_reml_exec                                                                                                                          \
            -regress_make_ideal_sum   sum_ideal.1D                                                                                                      \
            -regress_est_blur_errts                                                                                                                     \
            -regress_run_clustsim     no                                                                                                                \
            -html_review_style        pythonic                                                                                                          \
            -bash -execute                                                                                                                              \
            2>&1 | tee $OUTPUTPATH/log.afniproc.years.sub-{SUBJECT}


# report final exit status
exit_status=$?

if [ $exit_status -ne 0 ] ; then
echo "afni pipeline failed. See logs for details." >&2
exit 1
else
echo "Pipeline sucessed. Exiting"
fi



