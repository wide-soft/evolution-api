#!/bin/bash

#--------------------------------------------------------------------------
# Common functions for general scripts
#
# @author: Rodrigo Vieira - rodrigodelimavieira@gmail.com
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Global settings
#------------------------------------------------------------------------------

LOG_DIR="/var/log/scripts"

#------------------------------------------------------------------------------
# Standard log messages
#------------------------------------------------------------------------------
#
# Write messages to standard output and to a log file. Log messages will have
# this pattern:
# date_and_time hostname scriptname: log_level - log_message
# for instance:
# Feb 20 13:34:01 stark dbbackup: INFO - backup script finished without errors
#------------------------------------------------------------------------------

log () {
    _level="$1"
    _msg="$2"
    _datetime=$(date +"%b %e %T")
    _script=$(basename $(readlink -f "$0") | cut -d'.' -f1)
    _prefix="$(hostname -s) $_script: $_level -"
    _file="/tmp/${_script}.log"

    echo -e "$_prefix $_msg" |tee -a $_file
}

#------------------------------------------------------------------------------
# Log levels
#------------------------------------------------------------------------------

# if DEBUG is set to true within client script.
logdebug () {
    if ( $DEBUG );then
        log DEBUG "$@"
    fi
}

loginfo () {
    log INFO "$@"
}

logwarning () {
    log WARNING "$@"
}

logerror () {
    log ERROR "$@"
}

logwarn () {
    logwarning "$@"
}

logerr () {
    logerror "$@"
}

getenv () {
    # look for a variable on environment ou .env file
    # or use it's default value
    _env_var="$1"
    _default_value="$2" # or ""
    _dot_env="/root/.env"

    # is it defined on current environment?
    if [ -n "${!_env_var}" ];then
        echo "${!_env_var}"
    else
        # otherwise, try to load .env file
        [ -f "$_dot_env" ] && source  $_dot_env

        if [ -n "${!_env_var}" ];then
            echo "${!_env_var}"
        else
            # or just return the default value
            echo "$_default_value"
        fi
    fi
}
