"""Main module."""

import logging, os, shutil
import re
from pathlib import Path
import errorhandler
from typing import List, Tuple
from flywheel_gear_toolkit import GearToolkitContext
from fw_gear_afni_proc.fmriprep_to_afni_proc import concat_motion_file, concat_confounds, make_afni_events, download_event_files, make_union_mask
from fw_gear_afni_proc.from_template import proc
from fw_gear_afni_proc.support_functions import searchfiles, execute_shell, cleanup
from fw_gear_afni_proc.utils.command_line import exec_command

log = logging.getLogger(__name__)

# Track if message gets logged with severity of error or greater
error_handler = errorhandler.ErrorHandler()

# # Also log to stderr
# stream_handler = logging.StreamHandler(stream=sys.stderr)
# log.addHandler(stream_handler)


def prepare(
        gear_options: dict,
        app_options: dict,
) -> Tuple[List[str], List[str]]:
    """Prepare everything for the algorithm run.

    It should:
     - Install FreeSurfer license (if needed)

    Same for FW and RL instances.
    Potentially, this could be BIDS-App independent?

    Args:
        gear_options (Dict): gear options
        app_options (Dict): options for the app

    Returns:
        errors (list[str]): list of generated errors
        warnings (list[str]): list of generated warnings
    """
    # pylint: disable=unused-argument
    # for now, no errors or warnings, but leave this in place to allow future methods
    # to return an error
    errors: List[str] = []
    warnings: List[str] = []

    return errors, warnings
    # pylint: enable=unused-argument


def run(gear_options: dict, app_options: dict, gear_context: GearToolkitContext) -> int:
    """Run AFNI program using generic bids-derivative inputs.

    Arguments:
        gear_options: dict with gear-specific options
        app_options: dict with options for the BIDS-App

    Returns:
        run_error: any error encountered running the app. (0: no error)
    """

    # report selected config settings
    log.info("Using %s", app_options["run-level"])

    fw_client = gear_options["client"]
    subject = app_options["sid"]
    session = app_options["sesid"]
    workdir = app_options["work-dir"]

    if app_options["run-level"] == "afni-proc":
        log.info("Using Configuration Settings: ")

        log.parent.handlers[0].setFormatter(logging.Formatter('\t\t%(message)s'))
        #
        # log.info("DropNonSteadyState: %s", str(app_options["DropNonSteadyState"]))
        # if "DummyVolumes" in app_options:
        #     log.info("DummyVolumes: %s", str(app_options["DummyVolumes"]))
        log.info("evformat: %s", str(app_options["evformat"]))
        if "events-suffix" in app_options:
            log.info("events-suffix: %s", str(app_options["events-suffix"]))
        log.info("allow-missing-evs: %s", str(app_options["allow-missing-evs"]))
        log.info("Using afni script: %s", Path(gear_options["SCRIPT"]).name)
        log.parent.handlers[0].setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))

        # pull list of files from template
        func_files = proc.get_func_files(gear_options, app_options)
        regress_event_files = proc.get_event_files(gear_options, app_options)
        regress_motion_file = proc.get_motion_files(gear_options, app_options)
        regress_confound_file = proc.get_confound_files(gear_options, app_options)
        nvolumes = proc.get_dummy_volumes(gear_options, app_options)

        # get list of tasks from list of func files
        bids_names=[]
        for f in func_files:
            tmp = [a for a in Path(f).name.split(".")[0].split("_") if any(b in a for b in ["task-","acq-","rec-","dir-","run-","echo-","part-","chunk-"])]
            bids_names.append("_".join(tmp))

        # step 3: create 1D event files (time shift to match dropnonsteadystate value)
        files = []
        for name in bids_names:
            files.append(download_event_files(name, fw_client, dest_id=gear_options["destination-id"],
                                              workdir=os.path.dirname(func_files[0]), events_suffix=app_options["events-suffix"]))

        regress_event_labels = []
        for f in regress_event_files:
            regress_event_labels.append(os.path.basename(f).replace(".1D",""))

        event_files, event_labels = make_afni_events(files, nvolumes, app_options["trs"], regress_event_labels, write_as_married=app_options["write-as-married"])

        os.makedirs(os.path.dirname(regress_event_files[0]), exist_ok=True)
        for f in event_files:
            shutil.move(f, os.path.join(os.path.dirname(regress_event_files[0]), os.path.basename(f)))

        for f in regress_event_files:
            if not os.path.exists(f):
                log.warning("Event file not located: %s", os.path.basename(f))
                if app_options["allow-missing-evs"]:
                    # make empty regressor
                    cmd = "echo -1:1 > "+ f
                    execute_shell(cmd, dryrun=False, cwd=workdir)


        # get confound file list for motion and confounds steps
        files = []
        for name in bids_names:
            files.append(searchfiles(os.path.join(workdir, "fmriprep", "sub-" + subject, "ses-" + session, "func",
                                                  "*" + name + "*_desc-confounds_timeseries.tsv"))[0])

        # step 4: pass single concatenated motion file
        try:
            concat_motion_file(files, nvolumes, regress_motion_file)
        except:
            if app_options["pipeline"] is not "bids":
                log.warning("Unable to locate or concatenate head motion")

        # step 5: generate additional confound regressors...
        if app_options["confound-list"] and regress_confound_file:
            colnames = app_options["confound-list"].replace(" ", "").split(",")
            concat_confounds(files, colnames, nvolumes, regress_confound_file)

        # step 6: create full mask across all functional runs
        in_files = [s.replace("desc-preproc_bold.nii.gz", "desc-brain_mask.nii.gz") for s in func_files]
        make_union_mask(in_files)

        # make final script for run... apply lookup table
        runfile = proc.make_run_script(gear_options, app_options)

        #run!
        cmd = ["bash",runfile]
        if gear_options.config.get("gear-log-to-file"):
            cmd = cmd + [">", "output/log1.txt"]
        stdout, stderr, run_error = exec_command(
            cmd,
            dry_run=gear_options["dry-run"],
            shell=True,
            cont_output=True,
            cwd=gear_options["work-dir"]
        )

    elif app_options["run-level"] == "other":
        log.warning("Ignoring configuration settings: DropNonSteadyState, DummyVolumes, evformat, events-suffix, allow-missing-evs")
        log.info("Using afni script: %s", Path(gear_options["SCRIPT"]).name)

        # DO anything? or just run??
        # make final script for run... apply lookup table
        if check_for_special_chars(gear_options["SCRIPT"]):
            runfile = proc.make_run_script(gear_options, app_options)
        else:
            runfile = gear_options["SCRIPT"]

        cmd = ["bash", runfile]
        stdout, stderr, run_error = exec_command(
            cmd,
            dry_run=gear_options["dry-run"],
            shell=True,
            cont_output=True,
            cwd=gear_options["work-dir"]
        )

    # zip up results...
    cleanup(gear_options, app_options)

    return run_error


def check_for_special_chars(file_path):
    """Checks a text file for special characters.

    Args:
        file_path: The path to the text file.

    Returns:
        True if special characters are found, False otherwise.
    """

    with open(file_path, 'r') as file:
        for line in file:
            if re.search(r'[^a-zA-Z0-9\s]', line):  # Adjust the pattern to include allowed characters
                return True
    return False



