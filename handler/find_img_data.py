#!/usr/bin/env python3

import os
import sys
from pathlib import Path
from pydicom import dcmread
from presort_dicoms import presort

# presort can slow down ezBIDS as it examines every dicom, it's enabled/disabled
# by setting the PRESORT environment varibable to "true" or ""
presort_enabled = bool(os.getenv('PRESORT', 'false').lower() == 'true')
presort_enabled_pet = bool(os.getenv('PREESORT_PET', 'false').lower == 'true')

# if pet2bids is installed we use it wherever the PET data live
try:
    # import pypet2bids
    pet2bidsInstalled = True
    from pypet2bids import is_pet
except (ImportError, ModuleNotFoundError):
    pet2bidsInstalled = False
    print('pet2bids is not installed, using dcm2niix on PET directories instead')
    sys.exit(1)



def find_img_data(dir):
    '''
    Finds all directories that contain DICOM (or other) raw imaging data.
    If dcm2niix output (NIfTI, JSON files) uploaded instead, ezBIDS has separate process for detecting those files.

    Parameters
    ----------
    dir : string
        root-level directory of uploaded data
    '''
    hasImgData = False

    # MRI (raw only)
    for x in sorted(os.listdir(dir)):
        full_path = os.path.join(dir, x)
        if os.path.isdir(full_path):
            for f in sorted(os.listdir(full_path)):
                try:
                    read_file = dcmread(f'{full_path}/{f}')
                    if read_file.Modality == 'MR':
                        mri_dcm_dirs_list.append(full_path)
                        hasImgData = True
                        break
                except:
                    # Doesn't appear to be DICOM data, so skip
                    break

    # Complete search
    if not hasImgData:
        for x in sorted(os.listdir(dir)):
            full_path = os.path.join(dir, x)
            if os.path.isdir(full_path):
                find_img_data(full_path)


# change to input directory
root = sys.argv[1]
os.chdir(root)

mri_dcm_dirs_list = []
pet_ecat_files_list = []
pet_dcm_dirs_list = []
meg_data_list = []

root_full_path = str(Path(root).absolute())


# PET
pet_folders = [str(folder) for folder in is_pet.pet_folder(Path(root).resolve(), skim=True, njobs=4)]
pet_folders = [os.path.relpath(x, root) for x in pet_folders if x != '']
pet_folders = [os.path.join('.', x) for x in pet_folders]

if pet_folders:
    for pet in pet_folders:
        # See if we're dealing ECAT-formatted file(s)
        ecats = [x for x in os.listdir(pet) if x.endswith(tuple(['.v', '.v.gz']))]
        if len(ecats):
            for ecat in ecats:
                if ecat not in pet_ecat_files_list:
                    pet_ecat_files_list.append(f'{pet}/{ecat}')
        # See if we're dealing with DICOM files
        dcms = [
            x for x in os.listdir(pet)
            if not x.endswith(tuple(['.nii', '.nii.gz', '.v', '.v.gz', '.json', '.tsv']))
        ]
        if len(dcms) and pet not in pet_dcm_dirs_list:
            pet_dcm_dirs_list.append(pet)

# MEG
MEG_extensions = ['*.ds', '*.fif', '*.sqd', '*.con', '*.raw', '*.ave', '*.mrk', '*.kdf', '*.mhd', '*.trg', '*.chn', '*.dat']
for meg_ext in MEG_extensions:
    if meg_ext == '*.ds':
        type_search = 'd'
    else:
        type_search = 'f'

    find_cmd = os.popen(f"find . -maxdepth 9 -type {type_search} -name '{meg_ext}'").read()
    if find_cmd != '':
        meg_data_list.append(find_cmd)

if len(meg_data_list):
    # TODO - won't this remove different extensions?
    meg_data_list = [x for x in meg_data_list[0].split('\n') if x != '' and 'hz.ds' not in x]

# Save the MRI, PET, MEG, and NIfTI lists (if they exist) to separate files
file = open(f'{root}/dcm2niix.list', 'w')
if len(mri_dcm_dirs_list):
    for dcm in mri_dcm_dirs_list:
        if presort_enabled:
            presorted_dicoms = presort(dcm)
            for pre in presorted_dicoms:
                file.write(str(pre)+ '\n')
        else:
            file.write(dcm + '\n')
file.close()

if len(pet_dcm_dirs_list):
    file = open(f'{root}/pet2bids_dcm.list', 'w')
    for dcm in pet_dcm_dirs_list:
        if presort_enabled:
            presorted_folders = presort(dcm)
            for pre in presorted_folders:
                file.write(str(pre) + '\n')
        else:
            file.write(dcm + '\n')
    file.close()

if len(pet_ecat_files_list):
    file = open(f'{root}/pet2bids_ecat.list', 'w')
    for ecat in pet_ecat_files_list:
        file.write(ecat + '\n')
    file.close()

if len(meg_data_list):
    file = open(f'{root}/meg.list', 'w')
    for meg in meg_data_list:
        file.write(meg + '\n')
    file.close()
