#!/usr/bin/env bash

if [ -n "$GITHUB_WORKSPACE" ]
then
    rm -f /home/builder/workspace/*.old
    echo "Moving repository to github workspace"
    mv /home/builder/workspace/* $GITHUB_WORKSPACE/
    # make sure that the .db/.files files are in place
    # Note: Symlinks fail to upload, so copy those files
    cd $GITHUB_WORKSPACE
    rm aurci2.db aurci2.files
    cp aurci2.db.tar.gz aurci2.db
    cp aurci2.files.tar.gz aurci2.files
else
    echo "No github workspace known (GITHUB_WORKSPACE is unset)."
fi
