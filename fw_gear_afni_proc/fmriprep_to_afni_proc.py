import numpy as np
import pandas as pd
import re
import math
import logging
import os


from fw_gear_afni_proc.support_functions import execute_shell

log = logging.getLogger(__name__)


def make_afni_events(files, nvolumes, tr, all_labels, write_as_married = True):
    all_files = dict()
    for i in all_labels:
        all_files[i] = []

    log.info("Using DummyVolumes: %s", str(nvolumes))
    log.info("Timing offset applied to event files: -%s", str(nvolumes * tr))

    for l in all_labels:

        for file in files:
            df = pd.read_csv(file, sep="\t")

            outpath = os.path.join(os.path.dirname(file), "afni")
            os.makedirs(outpath, exist_ok=True)

            groups = df["trial_type"].unique()

            if l in groups:

                ev = df[df["trial_type"] == l]
                ev1 = ev.copy()
                if "weight" not in ev1.columns:
                    ev1.loc[:, "weight"] = pd.Series([1 for x in range(len(df.index))])

                ev1 = ev1.drop(columns=["trial_type"])
                ev1["onset"] = ev1["onset"] - nvolumes * tr
                if any(ev1["onset"] < 0):
                    ev1.loc[ev1["onset"] < 0,  "duration"] = ev1.loc[ev1["onset"] < 0, ["onset", "duration"]].sum(axis=1)
                    ev1.loc[ev1["onset"] < 0, "onset"] = 0

            else:
                ev1 = pd.DataFrame({"onset": -1, "duration": 1}, index=[0])

            filename = os.path.join(outpath,
                                    os.path.basename(file).replace(".tsv", "-" + l + ".txt"))
            if not write_as_married:
                ev1["duration"] = 1

            ev1.to_csv(filename, sep=" ", index=False, header=False)

            all_files[l].append(filename)

    # combine events...
    outfiles = []
    for g in all_files.keys():
        if all_files[g]:
            if not write_as_married:
                cmd = "timing_tool.py -fsl_timing_files " + " ".join(all_files[g]) + " -write_timing " + g + ".1D"
            else:
                cmd = "timing_tool.py -write_as_married -fsl_timing_files " + " ".join(all_files[g]) +" -write_timing " + g + ".1D"
            execute_shell(cmd, cwd=outpath)
            outfiles.append(os.path.join(outpath, g + ".1D"))

    return outfiles, all_files.keys()


def download_event_files(taskname, fw_client, dest_id=None, workdir=os.getcwd(), events_suffix=None):
    """
    Pull event files from flywheel acquisition. If more than one event file is uploaded, select based on "event-suffix"
    config option. If no events uploaded, log error.
    Args:
        taskname:
        fw_client:
        workdir:
        events_suffix:

    """

    acq, nii = find_matching_acq(taskname, fw_client, dest_id)

    counter = 0

    for f in acq.files:
        if "_events" in f.name:

            # secondary check for correct suffix if provided...
            if events_suffix and events_suffix not in f.name:
                continue

            f.download(os.path.join(workdir, f.name))
            log.info("Using event file: %s", f.name)
            filename = os.path.join(workdir, f.name)
            counter += 1

    if counter == 0:
        log.error("No event file located in flywheel acquisiton: %s", acq.id)

    if counter > 1:
        log.error(
            "Multiple event files in flywheel acquisition match selection criteria... not sure how to proceed")

    return filename


def find_matching_acq(bids_name, fw_client, destid):
    """
    Args:
        bids_name (str): partial filename used in HCPPipeline matching BIDS filename in BIDS.info
        context (obj): gear context
    Returns:
        acquisition and file objects matching the original image file on which the
        metrics were completed.
    """
    destination = fw_client.get(destid)
    session = fw_client.get_session(destination.parents["session"])

    # assumes reproin naming scheme for acquisitions!
    for acq in session.acquisitions.iter_find():
        full_acq = fw_client.get_acquisition(acq.id)
        if ("func-bold" in acq.label) and (bids_name in acq.label) and ("sbref" not in acq.label.lower()) and (
                "ignore-BIDS" not in acq.label):
            for f in full_acq.files:
                if bids_name in f.info.get("BIDS").get("Filename") and "nii" in f.name:
                    return full_acq, f


def concat_motion_file(files, nvolumes, outfile):
    """
    description...

    take fmriprep output motion parameters and structure like afni expects.
    AFNI units: degrees CCW, mm. Order: n (index) roll (I-S axis), pitch (R-L axis), yaw (A-P axis), dS, dL, dP
    fmriprep units: radians, mm. Order: rot_x, rot_y, rot_z, trans_x, trans_y, trans_z
    """
    all_confounds_df = pd.DataFrame()
    degrees_ = np.vectorize(math.degrees)
    for f in files:
        data = pd.read_csv(f, sep='\t')
        confounds_df = pd.DataFrame()
        for cc in ['rot_z', 'rot_x', 'rot_y', 'trans_z', 'trans_x', 'trans_y']:
            if cc in data.columns:
                if "rot" in cc:
                    data[cc] = degrees_(data[cc])
                confounds_df = pd.concat([confounds_df, data[cc]], axis=1)

        confounds_df = confounds_df.iloc[nvolumes:]
        all_confounds_df = pd.concat([all_confounds_df, confounds_df], axis=0)

    # save output motion file
    os.makedirs(os.path.dirname(outfile), exist_ok=True)
    all_confounds_df.to_csv(
        outfile,
        header=False, index=False,
        sep=" ", na_rep=0)


def concat_confounds(files, colnames, nvolumes, outfile):
    """
    Build a concatenated confounds file - look for confound path then concatenate together
    """

    log.info("Building extra confounds file...")
    all_confounds_df = pd.DataFrame()

    for idx, f in enumerate(files):
        confounds_df = pd.DataFrame()
        data = pd.read_csv(f, sep='\t')

        for cc in colnames:
            # look for exact matches...
            if cc in data.columns:
                confounds_df = pd.concat([confounds_df, data[cc]], axis=1)

            # handle regular expression entries
            elif any(special_char in cc for special_char in ["*", "^", "$", "+"]):
                pattern = re.compile(cc)
                for regex_col in [s for s in data.columns if bool(re.search(pattern, s))]:
                    confounds_df = pd.concat([confounds_df, data[regex_col]], axis=1)

        confounds_df.columns = ["run_" + str(idx).zfill(2) + "_" + s for s in confounds_df.columns]

        confounds_df = confounds_df.iloc[nvolumes:]
        # all_confounds_df = pd.concat([all_confounds_df, confounds_df], axis=1)

        # add zeros buffer
        arr = np.zeros([confounds_df.shape[0], all_confounds_df.shape[1]])
        df = pd.DataFrame(arr, columns=all_confounds_df.columns)

        arr = np.zeros([all_confounds_df.shape[0], confounds_df.shape[1]])
        df2 = pd.DataFrame(arr, columns=confounds_df.columns)

        all_confounds_df = pd.concat([all_confounds_df, df], axis=0, ignore_index=True)
        confounds_df = pd.concat([df2, confounds_df], axis=0, ignore_index=True)

        # combine final confounds set
        all_confounds_df = pd.concat([all_confounds_df, confounds_df], axis=1)

    if not all_confounds_df.empty:
        for idx, f in enumerate(files):
            cols = [c for c in all_confounds_df if "run_" + str(idx).zfill(2) in c]

            all_confounds_df.to_csv(
                os.path.join(os.path.dirname(f), "run_" + str(idx).zfill(2) + '-confounds.txt'),
                header=False, index=False, columns=cols, sep=" ", na_rep=0)

        os.makedirs(os.path.dirname(outfile), exist_ok=True)
        all_confounds_df.to_csv(outfile,
            header=False, index=False, sep=" ", na_rep=0)
    else:
        return all_confounds_df.columns


def make_union_mask(in_files):
    "3dmask_tool -inputs *mask.nii.gz -union -prefix full_mask.nii"
    cmd = "3dmask_tool -inputs " + " ".join(in_files) + " -union -prefix full_mask.nii"
    execute_shell(cmd, cwd=os.path.dirname(in_files[0]))

