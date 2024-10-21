import logging
import os
import subprocess as sp
import shlex

from fw_gear_afni_proc.support_functions import apply_lookup

log = logging.getLogger(__name__)


class proc:
    def get_func_files(gear_options: dict, app_options: dict):
        """
        Identify functional file paths from the template script -- using afni-proc command convention
        Args:
            gear_options (dict): options for the gear, from config.json
            app_options (dict): options for the app, from config.json

        Returns:
            app_options (dict): updated options for the app, from config.json
        """

        app_options["func_files"] = None

        template_file = gear_options["SCRIPT"]

        with open(template_file) as f:
            txt = f.read()

        cmd_long = shlex.split(txt)
        # func_files_strings = cmd_long[cmd_long.index("-dsets") + 1]
        this_flag = False
        func_files_strings = []
        for c in cmd_long:
            if this_flag and c[0] == "-":
                break
            if this_flag and c != "\n":
                func_files_strings.append(c)
            if c == "-dsets":
                this_flag = True

        # apply filemapper to each file pattern and store
        subdirs = get_subdirectories(gear_options["work-dir"])

        if "pipeline" in app_options:
            pass
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "fmriprep")):
            app_options["pipeline"] = "fmriprep"
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "bids-hcp")):
            app_options["pipeline"] = "bids-hcp"
        elif len(subdirs[0]) > 0:
            app_options["pipeline"] = os.path.basename(subdirs[0])
        else:
            log.error("Unable to interpret pipeline for analysis. Contact gear maintainer for more details.")

        lookup_table = {"WORKDIR": str(gear_options["work-dir"]), "PIPELINE": app_options["pipeline"], "SUBJECT": app_options["sid"],
                        "SESSION": app_options["sesid"]}

        func_files = []
        for f in func_files_strings:
            func_files.append(apply_lookup(f, lookup_table))
        log.info("Located functional files: \n%s", "\n".join(func_files))

        # check all func file paths exist, if not error and exit
        for f in func_files:
            if not os.path.exists(f):
                log.error("Missing functional file from template: %s", f)
                return

        app_options["func_files"] = func_files

        # pull the repetition time from the func file (needed later... assume TR is same across all inputs)
        cmd = "3dinfo -nt " + func_files[0]
        log.debug("\n %s", cmd)
        terminal = sp.Popen(
            cmd, shell=True, stdout=sp.PIPE, stderr=sp.PIPE, universal_newlines=True
        )
        stdout, stderr = terminal.communicate()
        log.info(stdout)
        log.info(stderr)
        app_options["nvols"] = float(stdout.strip("\n"))

        # repetition time
        cmd = "3dinfo -tr " + func_files[0] + " pixdim4"
        log.debug("\n %s", cmd)
        terminal = sp.Popen(
            cmd, shell=True, stdout=sp.PIPE, stderr=sp.PIPE, universal_newlines=True
        )
        stdout, stderr = terminal.communicate()
        app_options["trs"] = float(stdout.split('\n')[0])

        log.info("TR: %s", str(app_options["trs"]))

        return func_files

    def get_event_files(gear_options: dict, app_options: dict):
        """
        Identify event file paths from the template script -- using afni-proc command convention (we need to create these later on)
        Args:
            gear_options (dict): options for the gear, from config.json
            app_options (dict): options for the app, from config.json

        Returns:
            app_options (dict): updated options for the app, from config.json
        """

        app_options["event_files"] = None

        template_file = gear_options["SCRIPT"]

        with open(template_file) as f:
            txt = f.read()

        cmd_long = shlex.split(txt)
        this_flag = False;
        event_files_strings = []
        for c in cmd_long:
            if this_flag and c[0] == "-":
                break
            if this_flag and c != "\n":
                event_files_strings.append(c)
            if c == "-regress_stim_times":
                this_flag = True

        # apply filemapper to each file pattern and store
        if "pipeline" in app_options:
            pass
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "fmriprep")):
            app_options["pipeline"] = "fmriprep"
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "bids-hcp")):
            app_options["pipeline"] = "bids-hcp"
        else:
            log.error("Unable to interpret pipeline for analysis. Contact gear maintainer for more details.")

        lookup_table = {"WORKDIR": str(gear_options["work-dir"]), "PIPELINE": app_options["pipeline"], "SUBJECT": app_options["sid"],
                        "SESSION": app_options["sesid"]}

        event_files = []
        for f in event_files_strings:
            event_files.append(apply_lookup(f, lookup_table))

        app_options["event_files"] = event_files

        return event_files

    def get_motion_files(gear_options: dict, app_options: dict):
        """
        Identify motion file paths from the template script -- using afni-proc command convention (we need to create these later on)
        Args:
            gear_options (dict): options for the gear, from config.json
            app_options (dict): options for the app, from config.json

        Returns:
            app_options (dict): updated options for the app, from config.json
        """

        app_options["motion_file"] = None

        template_file = gear_options["SCRIPT"]

        with open(template_file) as f:
            txt = f.read()

        cmd_long = shlex.split(txt)
        this_flag = False;
        motion_file_strings = []
        for c in cmd_long:
            if this_flag and c[0] == "-":
                break
            if this_flag and c != "\n":
                motion_file_strings.append(c)
            if c == "-regress_motion_file":
                this_flag = True

        # apply filemapper to each file pattern and store
        if "pipeline" in app_options:
            pass
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "fmriprep")):
            app_options["pipeline"] = "fmriprep"
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "bids-hcp")):
            app_options["pipeline"] = "bids-hcp"
        else:
            log.error("Unable to interpret pipeline for analysis. Contact gear maintainer for more details.")

        lookup_table = {"WORKDIR": str(gear_options["work-dir"]), "PIPELINE": app_options["pipeline"],
                        "SUBJECT": app_options["sid"],
                        "SESSION": app_options["sesid"]}

        motion_file = []
        if not motion_file_strings:
            return None
        for f in motion_file_strings:
            motion_file.append(apply_lookup(f, lookup_table))

        app_options["motion_file"] = motion_file[0]

        return motion_file[0]

    def get_confound_files(gear_options: dict, app_options: dict):
        """
        Identify confound file paths from the template script -- using afni-proc command convention (we need to create these later on)
        Args:
            gear_options (dict): options for the gear, from config.json
            app_options (dict): options for the app, from config.json

        Returns:
            app_options (dict): updated options for the app, from config.json
        """

        app_options["confound_files"] = None

        template_file = gear_options["SCRIPT"]

        with open(template_file) as f:
            txt = f.read()

        cmd_long = shlex.split(txt)
        this_flag = False;
        confound_file_strings = []
        for c in cmd_long:
            if this_flag and c[0] == "-":
                break
            if this_flag and c != "\n":
                confound_file_strings.append(c)
            if c == "-regress_extra_ortvec":
                this_flag = True

        # apply filemapper to each file pattern and store
        if "pipeline" in app_options:
            pass
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "fmriprep")):
            app_options["pipeline"] = "fmriprep"
        elif os.path.isdir(os.path.join(gear_options["work-dir"], "bids-hcp")):
            app_options["pipeline"] = "bids-hcp"
        else:
            log.error("Unable to interpret pipeline for analysis. Contact gear maintainer for more details.")

        lookup_table = {"WORKDIR": str(gear_options["work-dir"]), "PIPELINE": app_options["pipeline"],
                        "SUBJECT": app_options["sid"],
                        "SESSION": app_options["sesid"]}

        confound_files = []
        if not confound_file_strings:
            return None
        for f in confound_file_strings:
            confound_files.append(apply_lookup(f, lookup_table))

        app_options["confound_files"] = confound_files[0]

        return confound_files[0]

    def get_dummy_volumes(gear_options: dict, app_options: dict):
        """
        Identify dummy volumes
        Args:
            gear_options (dict): options for the gear, from config.json
            app_options (dict): options for the app, from config.json

        Returns:
            app_options (dict): updated options for the app, from config.json
        """

        app_options["DummyVolumes"] = 0

        template_file = gear_options["SCRIPT"]

        with open(template_file) as f:
            txt = f.read()

        cmd_long = shlex.split(txt)
        this_flag = False

        for c in cmd_long:
            if this_flag and c[0] == "-":
                break
            if this_flag and c != "\n":
                app_options["DummyVolumes"] = int(c)
                app_options["DropNonSteadyState"] = True
            if c == "-tcat_remove_first_trs":
                this_flag = True

        log.info("Using DummyFrames: %s", app_options["DummyVolumes"])

        return app_options["DummyVolumes"]

    def make_run_script(gear_options: dict, app_options: dict):
        """
        Apply lookup table to all entrys and save run script
        Args:
            gear_options (dict): options for the gear, from config.json
            app_options (dict): options for the app, from config.json

        Returns:
            app_options (dict): updated options for the app, from config.json
        """

        template_file = gear_options["SCRIPT"]
        outfile = os.path.join(gear_options["work-dir"], "run_" + os.path.basename(template_file))
        with open(template_file) as f:
            txt = f.read()

        lookup_table = {"WORKDIR": str(gear_options["work-dir"]), "PIPELINE": app_options["pipeline"],
                        "SUBJECT": app_options["sid"],
                        "SESSION": app_options["sesid"]}

        txt_out = apply_lookup(txt, lookup_table)

        with open(outfile, "w") as f:
            for l in txt_out.split("\n"):
                f.write(l + "\n")

        app_options["run_script"] = outfile

        return outfile

def get_subdirectories(rootpath):
    subdirectories = []
    for root, dirs, files in os.walk(rootpath):
        for dir in dirs:
            subdirectories.append(os.path.join(root, dir))
    return subdirectories
