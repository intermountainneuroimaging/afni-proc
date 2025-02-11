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


def run(gear_options: dict, app_options: dict) -> int:
    """Run AFNI program using generic bids-derivative inputs.

    Arguments:
        gear_options: dict with gear-specific options
        app_options: dict with options for the BIDS-App

    Returns:
        run_error: any error encountered running the app. (0: no error)
    """

    log.info("Using afni script: %s", Path(gear_options["SCRIPT"]).name)

    # DO anything? or just run??
    # make final script for run... apply lookup table
    if check_for_special_chars(gear_options["SCRIPT"]):
        runfile = proc.make_run_script(gear_options, app_options)
    else:
        runfile = gear_options["SCRIPT"]

    # run!
    cmd = ["bash", runfile]
    if gear_options['config'].get("gear-log-to-file"):
        cmd = cmd + [">", os.path.join(gear_options["output-dir"], "log1.txt")]
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



