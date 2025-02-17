"""Parser module to parse gear config.json."""
from typing import Tuple
from zipfile import ZipFile
from flywheel_gear_toolkit import GearToolkitContext
import os
import logging
import errorhandler
import subprocess as sp
from pathlib import Path
from fw_gear_afni_proc.support_functions import execute_shell
from fw_gear_afni_proc.utils.bids.download_run_level import download_bids_for_runlevel
from fw_gear_afni_proc.utils.bids.run_level import get_analysis_run_level_and_hierarchy

log = logging.getLogger(__name__)

# Track if message gets logged with severity of error or greater
error_handler = errorhandler.ErrorHandler()

# when downloading BIDS Limit download to specific folders
DOWNLOAD_MODALITIES = ["anat", "func", "fmap", "dwi"]  # empty list is no limit

# Whether or not to include src data (e.g. dicoms) when downloading BIDS
DOWNLOAD_SOURCE = False

GEAR = "bids-fmriprep"
REPO = "flywheel-apps"
CONTAINER = Path(REPO).joinpath(GEAR)

def parse_config(
        gear_context: GearToolkitContext,
) -> Tuple[dict, dict]:
    """Parse the config and other options from the context, both gear and app options.

    Returns:
        gear_options: options for the gear
        app_options: options to pass to the app
    """
    # ##   Gear config   ## #
    errors = []

    gear_options = {
        "dry-run": gear_context.config.get("gear-dry-run"),
        "output-dir": gear_context.output_dir,
        "destination-id": gear_context.destination["id"],
        "work-dir": gear_context.work_dir,
        "client": gear_context.client,
        "environ": os.environ,
        "debug": gear_context.config.get("debug"),
        "config": gear_context.config,
        "SCRIPT": gear_context.get_input_path("SCRIPT")
    }


    # set the output dir name for the BIDS app:
    gear_options["output_analysis_id_dir"] = (
            gear_options["output-dir"] / gear_options["destination-id"]
    )

    # ##   App options:   ## #
    app_options_keys = [
        "run-level",
        "confound-list",
        "events-suffix",
        "evformat",
        "allow-missing-evs",
        "write-as-married"
    ]
    app_options = {key: gear_context.config.get(key) for key in app_options_keys}

    work_dir = gear_options["work-dir"]
    if work_dir:
        app_options["work-dir"] = work_dir

    # pull config settings
    gear_options["bash"] = {
        "common_command": "bash",
        "params": ""
    }

    level = log.getEffectiveLevel()
    log.info("Log level: %s",level)
    # test afni installation first
    cmd = "afni_system_check.py -check_all"
    log.info("\n %s", cmd)
    terminal = sp.Popen(
        cmd, shell=True, stdout=sp.PIPE, stderr=sp.PIPE, universal_newlines=True
    )
    stdout, stderr = terminal.communicate()
    log.info(stdout)
    log.info(stderr)

    cmd = "cp /root/abin//AFNI.afnirc ~/.afnirc"
    log.debug("\n %s", cmd)
    terminal = sp.Popen(
        cmd, shell=True, stdout=sp.PIPE, stderr=sp.PIPE, universal_newlines=True
    )
    stdout, stderr = terminal.communicate()
    log.debug(stdout)
    log.debug(stderr)

    cmd = "suma -update_env"
    log.debug("\n %s", cmd)
    terminal = sp.Popen(
        cmd, shell=True, stdout=sp.PIPE, stderr=sp.PIPE, universal_newlines=True
    )
    stdout, stderr = terminal.communicate()
    log.debug(stdout)
    log.debug(stderr)

    cmd = "apsearch -update_all_afni_help"
    log.debug("\n %s", cmd)
    terminal = sp.Popen(
        cmd, shell=True, stdout=sp.PIPE, stderr=sp.PIPE, universal_newlines=True
    )
    stdout, stderr = terminal.communicate()
    log.debug(stdout)
    log.debug(stderr)

    if gear_context.get_input_path("preprocessing-pipeline-zip"):
        # unzip input files
        gear_options["preproc_zipfile"] = gear_context.get_input_path("preprocessing-pipeline-zip")
        log.info("Inputs file path, %s", gear_options["preproc_zipfile"])
        unzip_inputs(gear_options, gear_options["preproc_zipfile"])

    else:
        # Given the destination container, figure out if running at the project,
        # subject, or session level.
        destination_id = gear_context.destination["id"]
        hierarchy = get_analysis_run_level_and_hierarchy(gear_context.client, destination_id)
        gear_name = gear_context.manifest["name"]
        config = gear_context.config
        # Create HTML file that shows BIDS "Tree" like output
        tree = True
        tree_title = f"{gear_name} BIDS Tree"

        error_code = download_bids_for_runlevel(
            gear_context,
            hierarchy,
            tree=tree,
            tree_title=tree_title,
            src_data=DOWNLOAD_SOURCE,
            folders=DOWNLOAD_MODALITIES,
            dry_run=gear_options["dry-run"],
            do_validate_bids=config.get("gear-run-bids-validation"),
        )
        if error_code > 0 and not config.get("gear-ignore-bids-errors"):
            errors.append(f"BIDS Error(s) detected.  Did not run {CONTAINER}")

        app_options["pipeline"] = "bids"

    # additional preprocessing input
    if gear_context.get_input_path("additional-input-one"):
        app_options["additional_input"] = True
        gear_options["additional_input_zip"] = gear_context.get_input_path("additional-input-one")
        log.info("Additional inputs file path, %s", gear_options["additional_input_zip"])
        unzip_inputs(gear_options, gear_options["additional_input_zip"])
    else:
        app_options["additional_input"] = False

    # confounds file input
    if gear_context.get_input_path("confounds-file"):
        app_options["confounds_default"] = False
        app_options["confounds_file"] = gear_context.get_input_path("confounds-file")
    else:
        app_options["confounds_default"] = True  # look for confounds in bids-derivative folder

    # events file input
    if gear_context.get_input_path("event-file"):
        app_options["events-in-inputs"] = True
        app_options["event-file"] = gear_context.get_input_path("event-file")

        if ".zip" in app_options["event-file"]:
            # event files passed as zip
            rcc, app_options["event_dir"] = unzip_inputs(gear_options, app_options["event-file"])

        else:
            app_options["event_dir"] = os.path.dirname(app_options["event-file"])

    else:
        app_options["events-in-inputs"] = False  # look for events in flywheel acquisition


    # building file mapper methods to generate bids filename and path
    destination = gear_context.client.get(gear_context.destination["id"])
    subject = gear_context.client.get(destination.parents.subject)
    session = gear_context.client.get(destination.parents.session)

    app_options["sid"] = subject.label
    app_options["sesid"] = session.label

    # check if tasks are exact match to existing acquisitions, or look for wildcard match
    acq_labels = [acq.label for acq in session.acquisitions.iter_find()]
    app_options["acq_labels"] = acq_labels

    # pull original file structure
    orig = []
    for path, subdirs, files in os.walk(gear_options["work-dir"]):
        for name in files:
            orig.append(os.path.join(path, name))

    gear_options["unzipped-files"] = orig

    return gear_options, app_options


def unzip_inputs(gear_options, zip_filename):
    """
    unzip_inputs unzips the contents of zipped gear output into the working
    directory.
    Args:
        gear_options: The gear context object
            containing the 'gear_dict' dictionary attribute with key/value,
            'gear-dry-run': boolean to enact a dry run for debugging
        zip_filename (string): The file to be unzipped
    """
    rc = 0
    outpath=[]
    # use linux "unzip" methods in shell in case symbolic links exist
    log.info("Unzipping file, %s", zip_filename)
    cmd = "unzip -qq -o " + zip_filename + " -d " + str(gear_options["work-dir"])
    execute_shell(cmd, cwd=gear_options["work-dir"])

    # if unzipped directory is a destination id - move all outputs one level up
    with ZipFile(zip_filename, "r") as f:
        top = [item.split('/')[0] for item in f.namelist()]
        top1 = [item.split('/')[1] for item in f.namelist()]

    log.info("Done unzipping.")

    if len(top[0]) == 24:
        # directory starts with flywheel destination id - obscure this for now...

        cmd = "mv "+top[0]+'/* . '
        rc = execute_shell(cmd, cwd=gear_options["work-dir"])
        if rc > 0:
            cmd = "cp -R " + top[0] + '/* . '
            execute_shell(cmd, cwd=gear_options["work-dir"])

        cmd = 'rm -R ' + top[0]
        rc = execute_shell(cmd, cwd=gear_options["work-dir"])

        for i in set(top1):
            outpath.append(os.path.join(gear_options["work-dir"], i))

        # get previous gear info
        gear_options["preproc_gear"] = gear_options["client"].get_analysis(top[0])
    else:
        outpath = os.path.join(gear_options["work-dir"], top[0])

    if error_handler.fired:
        log.critical('Failure: exiting with code 1 due to logged errors')
        run_error = 1
        return run_error

    return rc, outpath


