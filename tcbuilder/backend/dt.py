import os
import subprocess
import shutil
import tempfile
import logging
from tcbuilder.backend import ostree
from tcbuilder.errors import OperationFailureError, PathNotExistError, TorizonCoreBuilderError

# If OSTree finds a file named `devicetree` it will consider it as the only relevant
# device tree to deploy.
DT_OUTPUT_NAME = "devicetree"

log = logging.getLogger("torizon." + __name__)

def store_overlay_files(overlays, storage_dir, devicetree_out):
    src_ostree_archive_dir = os.path.join(storage_dir, "ostree-archive")
    repo = ostree.open_ostree(src_ostree_archive_dir)
    kernel_version = ostree.get_kernel_version(repo, ostree.OSTREE_BASE_REF)

    if devicetree_out is None:
        if os.path.exists(os.path.join(storage_dir, "dt")):
            store_overlay_dts_dir = os.path.join(storage_dir, "dt",
                "usr/lib/modules", kernel_version, "overlays")
        else:
            raise PathNotExistError("No device tree storage directory created inside Volume")
    else:
        if os.path.exists(os.path.abspath(devicetree_out)):
            store_overlay_dts_dir = os.path.join(devicetree_out, "usr/lib/modules",
                kernel_version, "overlays")
        else:
            raise PathNotExistError(f"Directory {devicetree_out} not found.")

    if os.path.exists(store_overlay_dts_dir):
        shutil.rmtree(store_overlay_dts_dir)

    os.makedirs(store_overlay_dts_dir)

    for overlay in overlays:
        shutil.copy(overlay, store_overlay_dts_dir)

    return store_overlay_dts_dir

def clear_applied_overlays(storage_dir):
    src_ostree_archive_dir = os.path.join(storage_dir, "ostree-archive")
    repo = ostree.open_ostree(src_ostree_archive_dir)
    kernel_version = ostree.get_kernel_version(repo, ostree.OSTREE_BASE_REF)

    if ostree.check_existance(repo, ostree.OSTREE_BASE_REF,
        os.path.join("/usr/lib/modules", kernel_version, "overlays")):
        # create whiteout for "overlays" directory,so it gets removed upon merging
        kernel_dir = os.path.join(storage_dir, "dt",
                "usr/lib/modules", kernel_version)
        if os.path.exists(kernel_dir):
            overlay_dts_dir =  os.path.join(kernel_dir, ".wh.overlays")
            with open(overlay_dts_dir, 'w'):
                pass
        else:
            raise PathNotExistError("No device tree storage directory created inside Volume")

def build_and_apply(devicetree, overlays, devicetree_out, includepaths):
    """ Compile and apply several overlays to an input devicetree

        Args:
            devicetree (str) - input devicetree
            overlays (str) - list of devicetree overlays to apply
            devicetree_out (str) - the output devicetree(with overlays) applied
            includepaths (list) - list of additional include paths

        Raises:
            FileNotFoundError: invalid file name or build errors
    """
    if not os.path.isfile(devicetree):
        raise TorizonCoreBuilderError("Missing input devicetree")

    tempdir = tempfile.mkdtemp()
    if overlays is not None:
        dtbos = []
        for overlay in overlays:
            if not os.path.exists(os.path.abspath(overlay)):
                raise PathNotExistError(f"{overlay} does not exist")

            dtbo = tempdir + "/" + os.path.basename(overlay) + ".dtbo"
            build(overlay, dtbo, includepaths)
            dtbos.append(dtbo)

        apply_overlays(devicetree, dtbos, devicetree_out)
    else:
        build(devicetree, devicetree_out, includepaths)

    shutil.rmtree(tempdir)

def build(source_file, outputpath=None, includepaths=None):
    """ Compile a dtbs file into dtb or dtbo output

        Args:
            source_file (str) - path of source device tree/overlay file
            outputpath (str) - output file name/folder, if None then extension
                is appended to source file name, if it's a folder file with dtb/dtbo
                extension is created
            includepaths (list) - list of additional include paths

        Raises:
            FileNotFoundError: invalid file name or build errors
            OperationFailureError: failed to build the source_file
    """

    if not os.path.isfile(source_file):
        raise PathNotExistError(f"Invalid device tree source file {source_file}")

    ext = ".dtb"

    with open(source_file, "r") as f:
        for line in f:
            if "fragment@0" in line:
                ext = ".dtbo"
                break
    if outputpath is None:
        outputpath = "./" + os.path.basename(source_file) + ext

    if os.path.isdir(outputpath):
        outputpath = os.path.join(
            outputpath, os.path.basename(source_file) + ext)


    cppcmdline = ["cpp", "-nostdinc", "-undef", "-x", "assembler-with-cpp"]
    dtccmdline = ["dtc", "-@", "-I", "dts", "-O", "dtb"]

    if includepaths is not None:
        if type(includepaths) is list:
            for path in includepaths:
                dtccmdline.append("-i")
                dtccmdline.append(path)
                cppcmdline.append("-I")
                cppcmdline.append(path)
        else:
            raise OperationFailureError("Please provide device tree include paths as list")

    tmppath = source_file+".tmp"

    dtccmdline += ["-o", outputpath, tmppath]
    cppcmdline += ["-o", tmppath, source_file]

    cppprocess = subprocess.run(
        cppcmdline, stderr=subprocess.PIPE, check=False)

    if cppprocess.returncode != 0:
        raise OperationFailureError("Failed to preprocess device tree.\n" +
                        cppprocess.stderr.decode("utf-8"))

    dtcprocess = subprocess.run(
        dtccmdline, stderr=subprocess.PIPE, check=False)

    if dtcprocess.returncode != 0:
        raise OperationFailureError("Failed to build device tree.\n" +
                    dtcprocess.stderr.decode("utf-8"))

    os.remove(tmppath)

def apply_overlays(devicetree, overlays, devicetree_out):
    """ Verifies that a compiled overlay is valid for the base device tree

        Args:
            devicetree (str) - path to the binary input device tree
            overlays (str,list) - list of overlays to apply
            devicetree_out (str) - input device tree with overlays applied

        Raises:
            OperationFailureError - fdtoverlay returned an error
    """

    if not os.path.exists(devicetree):
        raise PathNotExistError("Invalid input devicetree")

    fdtoverlay_args = ["fdtoverlay", "-i", devicetree, "-o", devicetree_out]
    if type(overlays) == list:
        fdtoverlay_args.extend(overlays)
    else:
        fdtoverlay_args.append(overlays)

    fdtoverlay = subprocess.run(fdtoverlay_args,
                                stderr=subprocess.PIPE,
                                check=False)
    # For some reason fdtoverlay returns 0 even if it fails
    if fdtoverlay.stderr != b'':
        raise OperationFailureError(f"fdtoverlay failed with: {fdtoverlay.stderr.decode()}")

    log.debug("Successfully applied device tree overlay(s)")

def get_ostree_dtb_list(ostree_archive_dir):
    repo = ostree.open_ostree(ostree_archive_dir)
    kernel_version = ostree.get_kernel_version(repo, ostree.OSTREE_BASE_REF)

    dt_list = []
    if ostree.check_existance(repo, ostree.OSTREE_BASE_REF,
        os.path.join("/usr/lib/modules", kernel_version, "devicetree")):
        dt_list.append({'path': os.path.join("/usr/lib/modules", kernel_version), 'name': "devicetree"})

    if ostree.check_existance(repo, ostree.OSTREE_BASE_REF,
                            os.path.join("/usr/lib/modules", kernel_version, "dtb")):
        dir_contents = ostree.ls(repo, os.path.join("/usr/lib/modules",
                                kernel_version, "dtb"), ostree.OSTREE_BASE_REF)
        for dtb in dir_contents:
            if dtb["name"].endswith(".dtb"):  # get only *.dtb
                path = os.path.join("/usr/lib/modules", kernel_version, "dtb")
                dt_list.append({'path': path, 'name': dtb["name"]})

    return dt_list

def get_dt_changes_dir(devicetree_out, arg_storage_dir):
    dt_out = ""
    storage_dir = os.path.abspath(arg_storage_dir)
    src_ostree_archive_dir = os.path.join(storage_dir, "ostree-archive")

    repo = ostree.open_ostree(src_ostree_archive_dir)
    kernel_version = ostree.get_kernel_version(repo, ostree.OSTREE_BASE_REF)

    if devicetree_out is None:
        dt_out = os.path.join(storage_dir, "dt")
        dt_out = os.path.join(dt_out, "usr/lib/modules", kernel_version, DT_OUTPUT_NAME)
    else:
        dt_out = os.path.join(devicetree_out, "usr/lib/modules", kernel_version, DT_OUTPUT_NAME)

    return dt_out

def create_dt_changes_dir(devicetree_out, arg_storage_dir):
    dt_out = ""
    dt_out = get_dt_changes_dir(devicetree_out, arg_storage_dir)

    if devicetree_out is None:
        storage_dir = os.path.abspath(arg_storage_dir)
        if os.path.exists(os.path.join(storage_dir, "dt")):
            shutil.rmtree(os.path.join(storage_dir, "dt"))

    os.makedirs(dt_out.rsplit('/', 1)[0])
    return dt_out

def copy_devicetree_bin_from_ostree(storage_dir, devicetree_bin):
    #copy user selected to /storage for further processing
    if os.path.exists(os.path.join(storage_dir, "tmp_devicetree.dtb")):
        os.remove(os.path.join(storage_dir, "tmp_devicetree.dtb"))

    dt_copied_path = os.path.join(storage_dir, "tmp_devicetree.dtb")

    src_ostree_archive_dir = os.path.join(storage_dir, "ostree-archive")
    repo = ostree.open_ostree(src_ostree_archive_dir)
    ostree.copy_file(repo, ostree.OSTREE_BASE_REF, devicetree_bin, dt_copied_path)

    return dt_copied_path

def copy_devicetree_bin_from_workdir(storage_dir, devicetree_bin):
    #copy user selected to /storage for further processing
    if os.path.exists(os.path.join(storage_dir, "tmp_devicetree.dtb")):
        os.remove(os.path.join(storage_dir, "tmp_devicetree.dtb"))

    dt_copied_path = os.path.join(storage_dir, "tmp_devicetree.dtb")

    shutil.copy(devicetree_bin, dt_copied_path)

    return dt_copied_path

def get_compatibilities_binary(file):
    """Get root "compatible" property as list of strings"""
    std_output = subprocess.check_output(["fdtget", file, "/", "compatible"])
    compatibility_list = std_output.decode('utf-8').strip().split()
    return compatibility_list

def get_default_include_dir(ostree_archive_dir):
    """Get default include directory"""
    repo = ostree.open_ostree(ostree_archive_dir)
    metadata, _, _ = ostree.get_metadata_from_ref(repo, ostree.OSTREE_BASE_REF)

    include_dirs = ["device-trees/include/"]
    if "oe.arch" in metadata:
        oearch = metadata["oe.arch"]
        if oearch == "aarch64":
            include_dirs.append("device-trees/dts-arm64/")
        elif oearch == "arm":
            include_dirs.append("device-trees/dts-arm32/")
        else:
            raise OperationFailureError(f"Unknown architecture {oearch}.")

    return include_dirs

def get_list_applied_dtbo_in_repo(storage_directory):
    storage_dir = os.path.abspath(storage_directory)
    src_ostree_archive_dir = os.path.join(storage_dir, "ostree-archive")

    repo = ostree.open_ostree(src_ostree_archive_dir)
    kernel_version = ostree.get_kernel_version(repo, ostree.OSTREE_BASE_REF)
    dir_contents = []
    if ostree.check_existance(repo, ostree.OSTREE_BASE_REF,
            os.path.join("/usr/lib/modules", kernel_version, "overlays")):
        dir_contents = ostree.ls(repo,
                os.path.join("/usr/lib/modules", kernel_version, "overlays"),
                ostree.OSTREE_BASE_REF)

    return dir_contents