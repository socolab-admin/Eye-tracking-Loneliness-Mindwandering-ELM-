# Eye-tracking-Loneliness-Mindwandering-ELM-
This repository serves as the central data storage and sharing platform for the Eye-tracking, Loneliness, and Mind-Wandering (ELM) project, supporting collaboration among researchers at the University of Southern California (USC) and Ohio State University (OSU). The project investigates whether loneliness is associated with idiosyncratic patterns of neural processing, visual attention, and various subjective states during naturalistic  and experimental tasks. The repository contains processed fNIRS, eye-tracking, and self-report data. Although the primary stakeholders are USC and OSU researchers working on the ELM project, the repository is publicly available to facilitate transparency, reproducibility, and secondary analyses by the broader scientific community.

## Dataset Overview
### UCLA Loneliness Scores
* Description: Totals of 20-item UCLA Loneliness Scale.
* Format: CSV
* Update Frequency: Static
* Size: ~1 KB
  
### fNIRS Video-Viewing
* Description: Processed fNIRS recordings collected during naturalistic video viewing tasks.
* Format: CSV
* Update Frequency: Static
* Size: ~1.7 GB

### fNIRS SART
* Description: Processed fNIRS recordings collected during the Sustained Attention to Response Task (SART).
* Format: MATLAB (.mat) & CSV
* Update Frequency: Static
* Size: ~1.3 GB

### Eye-Tracking Video-Viewing
* Description: Processed eye-tracking recordings collected during naturalistic video viewing tasks.
* Format: Gzip-compressed CSV (.csv.gz)
* Update Frequency: Static
* Size: ~2.95 GB

### Eye-Tracking SART 
* Description: Processed eye-tracking recordings collected during the Sustained Attention to Response Task (SART).
* Format: Gzip-compressed CSV (.csv.gz)
* Update Frequency: Static
* Size: ~1 GB

### Synchronized Video-Viewing 
* Description: Time-aligned processed eye-tracking and fNIRS datasets from the video-viewing task, synchronized using Lab Streaming Layer (LSL) streams recorded during data acquisition. Outputs include aligned multimodal signals prepared for integrated eye-tracking–fNIRS analyses.
* Format: CSV
* Update Frequency: Static
* Size: ~1.45 GB

### Synchronized SART 
* Description: Time-aligned processed eye-tracking and fNIRS datasets from the SART task, synchronized using Lab Streaming Layer (LSL) streams and PsychoPy SART logs recorded during data acquisition. Outputs include aligned multimodal signals prepared for integrated eye-tracking–fNIRS analyses and SART trials/probe timing.
* Format: CSV
* Update Frequency: Static
* Size: ~550 MB

## Repository Structure
```text
├── data/
│   ├── raw/                          # Original eye-tracking, fNIRS, and LSL/PsychoPy logs
│   ├── processed/                    # Processed datasets for downstream analyses
│   │   ├── eye_processed_videos/
│   │   ├── eye_processed_SART/
│   │   ├── fNIRS_processed_videos/
│   │   ├── fNIRS_processed_SART/
│   │   ├── eye_sync_fNIRS_videos/
│   │   └── eye_sync_fNIRS_SART/
│   └── qc/                           # Quality-control reports and preprocessing summaries
│
├── docs/                             # Documentation, protocols, and data dictionaries
├── scripts/                          # R and MATLAB preprocessing/analysis pipelines
├── .gitignore
└── README.md
```


## Data Pipeline & Architecture
```mermaid
flowchart TD

A[Raw fNIRS Data]
B[Raw Eye-Tracking EDF Files]
C[Loneliness / Survey Data]
D[Lab Streaming Layer LSL Streams]
E[SART PsychoPy Log Files]

QC[Quality Control and Diagnostics]
OUT[Statistical / ML Analyses]

subgraph VV[Video-Viewing Pipeline]
    direction TB
    A --> VV1[fNIRS Video-Viewing Preprocessing]
    VV1 --> VV2[fNIRS Video-Viewing Postprocessing]
    VV2 --> VV3[Processed fNIRS Video-Viewing Dataset]

    B --> VV4[EDFConvert]
    VV4 --> VV5[Video-Viewing Gaze Parse]
    VV5 --> VV6[Eye-Tracking Video-Viewing Preprocessing]
    VV6 --> VV7[Eye-Tracking Video-Viewing Postprocessing]
    VV7 --> VV8[Processed Eye-Tracking Video-Viewing Dataset]

    D --> VV9[Eye-fNIRS Synchronization]
    VV3 --> VV9
    VV8 --> VV9
    VV9 --> VV10[Synchronized Video-Viewing Dataset]

    VV3 --> VV11[Video-Viewing Statistical / ML Analysis]
    VV8 --> VV11
    VV10 --> VV11
end

subgraph SART[SART Pipeline]
    direction TB
    A --> S1[fNIRS SART Preprocessing]
    S1 --> S2[fNIRS SART Postprocessing]
    S2 --> S3[SART Stimulus Builder]
    E --> S3
    S3 --> S4[Processed fNIRS SART MAT and HbO/HbR CSV]

    B --> S5[EDFConvert]
    S5 --> S6[SART Gaze Parse]
    S6 --> S7[Eye-Tracking SART Preprocessing]
    S7 --> S8[Eye-Tracking SART Postprocessing]
    S8 --> S9[Processed Eye-Tracking SART Dataset]

    D --> S10[Eye-fNIRS Synchronization]
    S4 --> S10
    S9 --> S10
    S10 --> S11[Synchronized SART Dataset]

    S4 --> S12[SART Statistical / ML Analysis]
    S9 --> S12
    S11 --> S12
end

C --> OUT
VV10 --> OUT
VV11 --> OUT
S11 --> OUT
S12 --> OUT

VV1 --> QC
VV2 --> QC
VV6 --> QC
VV7 --> QC
VV9 --> QC
S1 --> QC
S2 --> QC
S7 --> QC
S8 --> QC
S10 --> QC
S3 --> QC
```
## Data Dictionary 
Detailed descriptions of each processed dataset, including variable definitions, data types, and metadata, are available in the repository's docs/dictionary.md.

## Data Governance, Privacy & Licensing
### Data Quality Constraints
Processed datasets are generated through repository-specific preprocessing, synchronization, and quality-control pipelines. Quality-control summaries and preprocessing diagnostics are stored in `data/qc/`, while detailed dataset descriptions, variable definitions, and metadata are documented in `docs/dictionary.md`.

### PII / Privacy Note
All datasets included in this repository have been de-identified prior to inclusion. Personally identifiable information (PII) and other sensitive participant information have been removed or excluded from the shared datasets. This repository is intended solely for storing and sharing de-identified research data and associated analysis resources for the Eye-tracking, Loneliness, and Mind-Wandering (ELM) project.

### License
This repository is distributed under the **MIT License**. See the [`LICENSE`](LICENSE) file for additional information.

### Contributors & Contact
**Repository Maintainer:** Evans Alvarez — [evansalv@usc.edu](mailto:evansalv@usc.edu)

**Collaborating Institutions:** University of Southern California (USC) and The Ohio State University (OSU)

**Repository:** https://github.com/socolab-admin/Eye-tracking-Loneliness-Mindwandering-ELM-


