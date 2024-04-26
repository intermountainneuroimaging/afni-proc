# AFNI and afni_proc.py for Flywheel

(HPC Compatible) AFNI (Analysis of Functional NeuroImages) and AFNI's afni_proc.py is a program meant to create single subject processing scripts for task, resting state or surface based analyses. Afni_prog can be used to compute general linear model beta weights for task based fMRI analysis. This gear can be used to process a number of input tpyes including raw data, or preprocessed data using a BIDS compliant analyses (e.g. fmriprep or HCPPipeline). For examples of the afni_proc script used in flywheel see our "examples".

## Overview
This gear should be run on raw or preprocessed datasets that are in a BIDS derivative format (BIDS derivative info here). Two example compliant preprocessing flywheel gears are: (1) bids-fmriprep and (2) bids-hcp v.^1.2.5_4.3.0_inc1.5.1. The gear leverages the expected output format of a BIDS derivative dataset with a required gear input "SCRIPT" to assign fmri preprocessed images, high resolution T1 images, confounds, and event files within afni_proc or other generic afni scripts. Information leveraged from the flywheel database include the subject and session id as well as stored event files. Multiple runs can also be included, and should be indicated the proper run order in the afni script (see examples).

## Important Notes
Many assumptions are made when applying the afni script. We suggest running the gear in dry mode to generate the relevant input files and full afni script before running the gear in full. Use "dry-run" outputs to locally test or change afni scripts to maximize the effectiveness of flywheel parallel computing. Review the Troubleshooting section for more information on identifying and correcting issues. 

## Required Inputs

`SCRIPT`: AFNI script used to run afni program. Placeholders (described below) should be used where needed in the file path to allow the script to be used as a template across subjects or sessions.

`preprocessing-pipeline-zip`: (Optional) Select preprocessing output directory zip. Preprocessing outputs must be in bids derivative format. Example compatible pipelines: fmriprep, bids-hcp. If preprocessing directory not passed, gear assumes analysis should be run using BIDS raw data.

## Optional inputs

`additional-input-one`: (Optional) Additional preprocessing output directory. Preprocessing outputs must be in bids derivative format. 

`confounds-file`: (Optional) Additional input used as confound timeseries in 3dDeconvolve. If no input is passed, default confounds file is used from bids derivative directory '*counfound_timeseries.tsv'.

`event-file`: Explanatory variable (EVs) custom text files. Identify in config options the event files type (BIDS-Formatted|FSL-3 Column Format|FSL-1 Entry Per Volume). If not event file is passed, events will be downloaded from flywheel acquisition.


## Configuration 

`events-suffix`: suffix used to select correct events file from bids curated dataset. Events may be pulled directly from acquisition container if no event file is passed as input.

`output-name`: [NAME].subj directory name. If left blank, output name will be drawn from the template file.

`confound-list`: Comma seperated list of components to be included in glm confounds. Confound timeseries will be pulled from confound file in inputs if passed, otherwise defaults to using bids derivative file '*counfound_timeseries.tsv'. Example entry: rot_x, rot_y, rot_z, trans_x, trans_y, trans_z. If left blank no confounds will be included in feat analysis. Python regular expressions may be used to select variable number of components.

`DropNonSteadyState`: set whether or not to remove XX number of initial non-steady state volumes. If no value is passed in 'DummyVolumes', non-steady state number is taken from mriqc IQMs, if neither are defined, an error will be returned.

`DummyVolumes`: Number of dummy volumes to ignore at the beginning of scan. Leave blank if you want to use the non-steady state volumes recorded in mriqc IQMs.

`evformat`: (Default: BIDS-Formatted) Select type of file where events are stored. Selected format should match format provided in the events input file, or files downloaded directly from flywheel acquisition. If format passed is not AFNI compatible, update format to match AFNI requirements before running analysis. Options: BIDS-Formatted|FSL-3 Column Format|FSL-1 Entry Per Volume.

`gear-log-level`: Gear Log verbosity level (ERROR|WARNING|INFO|DEBUG)

`gear-dry-run`: Do everything except actually executing gear

`gear-writable-dir`: Gears expect to be able to write temporary files in /flywheel/v0/.  If this location is not writable (such as when running in Singularity), this path will be used instead.  The gear creates a large number of files so this disk space should be fast and local.

`slurm-cpu`: [SLURM] How many cpu-cores to request per command/task. This is used for the underlying '--cpus-per-task' option. If not running on HPC, then this flag is ignored

`slurm-ram`: [SLURM] How much RAM to request. This is used for the underlying '--mem-per-cpu' option. If not running on HPC, then this flag is ignored

`slurm-ntasks`: [SLURM] Total number of tasks/commands across all nodes (not equivalent to neuroimaging tasks). Using a value greater than 1 for code that has not been parallelized will not improve performance (and may break things).

`slurm-nodes`: [SLURM] How many HPC nodes to run on

`slurm-partition`: [SLURM] Blanca, Alpine, or Summit partitions can be entered

`slurm-qos`: [SLURM] For Blanca the QOS has a different meaning, ie blanca-ics vs blanca-ibg, etc. For Alpine and Summit, the QOS should be set to normal if running a job for 1 day or less, and set to long if running a job with a maximum walltime of 7 days

`slurm-account`: [SLURM] For Blanca the ACCOUNT should be set to the sub-account of choice (e.g. blanca-ics-rray). For Alpine, the account should be set to ucb-general, or the specialized account granted by RC: ucb278_asc1

`slurm-time`: [SLURM] Maximum walltime requested after which your job will be cancelled if it hasn't finished. Default to 1 day

`slurm-xnode`: [SLURM] List of nodes to exlcude when launching slurm script (e.g. bnode0101,bnode0102)

## Building a Template AFNI Script
The flywheel gear is built around the use of a template afni script file. Where necessary, the flywheel gear will create relevant helper files (e.g. concatenated motion file dfile_all.1D) before analysis. It's the user's responsibility to ensure the information in the template is correct and applies all necessary steps in the analysis. 

- **AFNI input file paths.** Placeholders for each input file should be added to the script file. The Flywheel gear uses a generic "Lookup" table to replace placeholder arguments in the filepath. Currently, the following lookup table placeholders are recognized:   
  >   `PIPELINE`   # name of the preprocessing parent directory (e.g. fmriprep)  
  > `SUBJECT`      # subject label in flywheel (attached to current analysis, e.g. 001)  
  > `SESSION`      # session label in flywheel (attached to current analysis, e.g. S1)  
  > `TASK`         # task name passed in task list  
  > `WORKDIR`      # placeholder for the work directory where analysis is run 

    Putting it all together, the file paths should look something like:  
`{WORKDIR}/{PIPELINE}/sub-{SUBJECT}/ses-{SESSION}/func/sub-{SUBJECT}_ses-{SESSION}_task-{TASK}_space-MNI152NLin6Asym_desc-preproc_bold.nii.gz`  

**Important Notes:**  
The file paths including the placeholders must follow the template shown above exactly, each placeholder variable must be written with {} and in all upper case. If additional lookup table variables are needed, please contact the gear developers.  

- **AFNI stimulus timing files.** If users are running afni_proc including run specific stimulus timing files, the filename generated from BIDS Formatted events are critically important. Event naming within the BIDS Formatted events file will be used as the file names for all stimuli. 

**`func-bold_task-experiment_run-01_desc-block_events.tsv`**

| Onset | Duration | trial_type |  
|-------|----------|------------|
| 10    | 3        | conditionA |
| 22    | 5        | conditionB |
| 35    | 3        | conditionA |
| 65    | 3        | conditionC |

**Code Snippet** `run_afni_proc.sh` 
```
[other afni_proc options here...]
-regress_stim_times                                        \
      {WORKDIR}/{SUBJECT}/events/conditionA.1D             \
      {WORKDIR}/{SUBJECT}/events/conditionB.1D             \
      {WORKDIR}/{SUBJECT}/events/conditionC.1D             \
-regress_stim_labels                                       \
      conditionA                                           \
      conditionB                                           \
      conditionC                                           \
-regress_stim_types AM2 AM2 AM2                            \
```

As you can see from the example above, the conditions labeled in the *events.tsv file should exactly match the stimulus timing filenames within the afni-script template.

## Using Python Regular Expressions
Selecting confounds to include as regressors of no-interest can be done using the config setting "confound-list". Use regular expressions where necessary to select a sub-group of all columns. For example "^rot_x" can be used to select all x rotational columns: rot_x, rot_x_derivative1, rot_x_power2, and rot_x_derivative1_power2. Refer to python's re package for more information on using python regular expressions [here](https://docs.python.org/3/howto/regex.html).

## Building Event Files
The flywheel afni-proc gear is designed to act on 4 types of event files: 
1. BIDS-Formatted
2. FSL-3 Column Format
3. FSL-1 Entry Per Volume 
4. AFNI 1D Format

Familiarize your self with the format of each file type by exploring the AFNI documentation <link> and BIDS specifications <link>. Examples of each file type are also included in the "examples" directory in this project. Be aware, BIDS-Formatted event files (see example above) will be automatically converted to AFNI 1D format for ANFI analysis (recommended). 

## Tips for Success:
Before running a full analysis, we recommend starting by running the gear in dry-run mode to generate all necessary input files (specific to the flywheel gear processing). Using these dry-run files, test the sucess of the analysis on a local environment where you can quickly modify analysis steps or inputs as needed. Once the analysis is running as expect, run the flywheel gear again as a full analysis. You are all set!