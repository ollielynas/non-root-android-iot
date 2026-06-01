
if [[ "$@" == *"--download"* ]]; then 
    echo "$(date): $@" >> log.txt 
fi

if [[ "$@" == *"--upload"* ]]; then 
    ./upload.sh --text "$@"
fi