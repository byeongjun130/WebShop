#!/bin/bash

# Displays information on how to use script
helpFunction()
{
  echo "Usage: $0 [-d small|all]"
  echo -e "\t-d small|all - Specify whether to download entire dataset (all) or just 1000 (small)"
  exit 1 # Exit script after printing help
}

# Get values of command line flags
while getopts d: flag
do
  case "${flag}" in
    d) data=${OPTARG};;
  esac
done

if [ -z "$data" ]; then
  echo "[ERROR]: Missing -d flag"
  helpFunction
fi

# Guard: abort if the active `python` is not CPython. conda-forge's `openjdk`
# used to resolve to a GraalVM build whose post-link step replaced
# `$CONDA_PREFIX/bin/python` with GraalPy, breaking every CPython C-extension
# (numpy, regex, jnius, ...). See `zulu-openjdk` pin below.
impl=$(python -c "import sys; print(sys.implementation.name)")
if [ "$impl" != "cpython" ]; then
  echo "[ERROR]: active python is '$impl', expected 'cpython'."
  echo "         Recreate the env: conda env remove -n webshop && \\"
  echo "                           conda create -n webshop python=3.8 -y"
  exit 1
fi

# Install Python Dependencies
pip install -r requirements.txt;

# Install Environment Dependencies via `conda`
# The pytorch-channel `faiss-cpu` is linked against `libmkl_intel_lp64.so.1`,
# but conda-forge's current `mkl` (>=2023) only ships `.so.2` — an ABI
# mismatch that hides behind a vague `ImportError` at `import faiss`.
# conda-forge's `faiss-cpu` is OpenBLAS-linked and sidesteps MKL entirely.
conda install -c conda-forge faiss-cpu -y;
# conda-forge's `openjdk=11` resolves to a GraalVM build whose post-link
# script overwrites `$CONDA_PREFIX/bin/python` with GraalPy, breaking every
# CPython C-extension (numpy, regex, jnius, ...). Conda-forge `openjdk=21`
# is a stock HotSpot JDK — pyserini/Lucene 9 runs fine on 21.
conda install -c conda-forge openjdk=21 -y;

# Download dataset into `data` folder via `gdown` command
mkdir -p data;
cd data;
if [ "$data" == "small" ]; then
  gdown https://drive.google.com/uc?id=1EgHdxQ_YxqIQlvvq5iKlCrkEKR6-j0Ib; # items_shuffle_1000 - product scraped info
  gdown https://drive.google.com/uc?id=1IduG0xl544V_A_jv3tHXC0kyFi7PnyBu; # items_ins_v2_1000 - product attributes
elif [ "$data" == "all" ]; then
  gdown https://drive.google.com/uc?id=1A2whVgOO0euk5O13n2iYDM0bQRkkRduB; # items_shuffle
  gdown https://drive.google.com/uc?id=1s2j6NgHljiZzQNL3veZaAiyW_qDEgBNi; # items_ins_v2
else
  echo "[ERROR]: argument for `-d` flag not recognized"
  helpFunction
fi
gdown https://drive.google.com/uc?id=14Kb5SPBk_jfdLZ_CDBNitW98QLDlKR5O # items_human_ins
cd ..

# Download spaCy large NLP model
python -m spacy download en_core_web_lg

# Build search engine index
cd search_engine
mkdir -p resources resources_100 resources_1k resources_100k
python convert_product_file_format.py # convert items.json => required doc format
mkdir -p indexes
./run_indexing.sh
cd ..

# Create logging folder + samples of log data
get_human_trajs () {
  PYCMD=$(cat <<EOF
import gdown
url="https://drive.google.com/drive/u/1/folders/16H7LZe2otq4qGnKw_Ic1dkt-o3U9Zsto"
gdown.download_folder(url, quiet=True, remaining_ok=True)
EOF
  )
  python -c "$PYCMD"
}
mkdir -p user_session_logs/
cd user_session_logs/
echo "Downloading 50 example human trajectories..."
get_human_trajs
echo "Downloading example trajectories complete"
cd ..