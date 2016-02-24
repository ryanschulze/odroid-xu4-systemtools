#!/bin/bash

#===============================================================================
#
#          FILE:  odroid-fan-control.sh
#
#         USAGE:  ./odroid-fan-control.sh
#
#   DESCRIPTION:  Fan speed control script to dynamically adjust the speed 
#                 according to the CPU temperature. Tested on a XU4.
#
#                 Based off the XU3 Script by nthx
#                 https://github.com/nthx/odroid-xu3-fan-control
#
#         NOTES:  
#                 exit codes:
#                   1 - script wasn't called with root privileges
#                   2 - script couldn't access required files
#                   3 - pidfile found, only run one instance of the script
#
#        AUTHOR:  Ryan Schulze (rs), ryan@ryanschulze.net
#       VERSION:  1.0
#       CREATED:  08/21/2015 01:12:23 PM CDT
#===============================================================================

# If the script tries to use an unset variable, bail out
set -o nounset


# Read configuration variable file if it is present
[ -r /etc/default/odroid-fan-control ] && . /etc/default/odroid-fan-control

FAN_VERBOSE=${FAN_VERBOSE:-true}
FAN_DEBUG=${FAN_DEBUG:-false}
FAN_LED=${FAN_LED:-false}

# check if we are root
if (( EUID != 0 )); then
   echo "This script must be run as root:" >&2
   echo "sudo ${0}" >&2
   exit 1
fi

#===============================================================================
# Configuration
#===============================================================================
declare -A CONFIG
CONFIG[CHECK_INTERVAL]=${CONFIG_CHECK_INTERVAL:-2}  # how often to check the temperature (in seconds)
CONFIG[MIN_FAN_ACTIVE]=${CONFIG_MIN_FAN_ACTIVE:-15} # if fan turns on, leave it on for at least x seconds
CONFIG[MIN_SPEED]=${CONFIG_MIN_SPEED:-80}           # minimum fan speed (when on)
CONFIG[MAX_SPEED]=${CONFIG_MAX_SPEED:-255}          # maximum fan speed
CONFIG[MIN_TEMP]=${CONFIG_MIN_TEMP:-55}             # temperature when we turn the fan on
CONFIG[MAX_TEMP]=${CONFIG_MAX_TEMP:-80}             # temperature where we hit maximum fan speed
CONFIG[LOGGER_NAME]='odroid-fan-control' # syslog name

#===============================================================================
# Device path/file settings
#===============================================================================
declare -A DEVICE
DEVICE[FAN]="$(find /sys/devices -type d -name "odroid_fan*" | head -1)"
# XU3 should be /sys/devices/odroid_fan.14, XU4 should be /sys/devices/odroid_fan.13
# use whatever we find
DEVICE[FAN_MODE]="${DEVICE[FAN]}/fan_mode"
DEVICE[FAN_SPEED]="${DEVICE[FAN]}/pwm_duty"
DEVICE[TEMPERATURE]="/sys/devices/virtual/thermal/thermal_zone0/temp"
DEVICE[LED]="$(find /sys/devices -type d -name "leds*" | head -1)"
DEVICE[LED_COLOR]='blue:heartbeart'
DEVICE[LED_PATH]="${DEVICE[LED]}/leds/${DEVICE[LED_COLOR]}/"

#===  FUNCTION  ================================================================
#          NAME:  log 
#   DESCRIPTION:  output information to syslog if FAN_VERBOSE = true
#===============================================================================
function log() {
	${FAN_VERBOSE} && logger -t ${CONFIG[LOGGER_NAME]} "${@}"
	${FAN_DEBUG} && echo "${@}"
}

#===============================================================================
# Check pidfile
#===============================================================================
PIDFILE='/var/run/odroid-fan-control.pid'
if [[ -e ${PIDFILE} ]] ; then
	log "existing pidfile found (${PIDFILE}), delete if stale"
	exit 3
fi
echo $$ > ${PIDFILE}

#===  FUNCTION  ================================================================
#          NAME:  cleanup 
#   DESCRIPTION:  make sure fan control is set back to 'auto' when script ends
#===============================================================================
function cleanup() {
	log "event: quit; fan control: auto"
	# revert fan mode back to auto
	echo '1' > ${DEVICE[FAN_MODE]}
	rm ${PIDFILE} 2>/dev/null
	exit 0
}
trap cleanup EXIT TERM INT

#===  FUNCTION  ================================================================
#          NAME:  temperature_short 
#   DESCRIPTION:  convert temperature to the 'normal' human expected format
#===============================================================================
function temperature_short() {
	# default to 100°C, better to turn the fan on than off if something isn't right
	echo "scale=0;${1:-100000} / 1000" | bc
}

#===  FUNCTION  ================================================================
#          NAME:  get_current_temperature 
#   DESCRIPTION:  get raw temperature data
#===============================================================================
function get_current_temperature() {
	# get the highest reported system temperature
	temperature_short "$(cat ${DEVICE[TEMPERATURE]})"
}

#===  FUNCTION  ================================================================
#          NAME:  set_fan_speed 
#   DESCRIPTION:  set and log fan speed changes if needed
#===============================================================================
function set_fan_speed() {
	# only change and log speed if there really is a change required
	if [[ "${current_fan_speed}" != "${new_fan_speed}" ]]; then
		
		# make sure fan mode is set to manual
		echo '0' > ${DEVICE[FAN_MODE]}
		
		if [[ ${new_fan_speed} -gt 1 ]]; then
			# make sure fan runs at least CONFIG[MIN_FAN_ACTIVE] seconds
			fan_active_until=$(date +%s --date="${CONFIG[MIN_FAN_ACTIVE]} seconds")
		elif [[ ${new_fan_speed} -eq 1 && $(date +%s) -le ${fan_active_until} ]]; then
			# set fan speed to minium until fan can turn off
			new_fan_speed=${CONFIG[MIN_SPEED]}
		fi

		echo "${new_fan_speed}" > ${DEVICE[FAN_SPEED]}
		current_fan_speed=${new_fan_speed}
		log "event: adjust; temp: ${current_temp}°C; speed: ${new_fan_speed}"

		${FAN_LED} && if [[ ${new_fan_speed} -gt 1 ]]; then
			led on
		else
			led off
		fi
	fi
}

#===  FUNCTION  ================================================================
#          NAME:  check_required_file 
#   DESCRIPTION:  check if a file exists, exit if it is missing
#===============================================================================
function check_required_file() {
	if [[ ! -f ${2:-} ]]; then
		log "event: could not find the required file for ${1:-}: ${2:-}"
		exit 2
	fi
}

#===  FUNCTION  ================================================================
#          NAME:  led 
#   DESCRIPTION:  control the LED to show if fan is on or off
#===============================================================================
function led() {
	case ${1:-} in
		setup )
			echo none > "${DEVICE[LED_PATH]}/trigger"
			led off
			;;
		on )
			echo 1 > "${DEVICE[LED_PATH]}/brightness"
			;;
		off )
			echo 0 > "${DEVICE[LED_PATH]}/brightness"
			;;
	esac
}

#===============================================================================
# check if we can access all the required files/devices
#===============================================================================
check_required_file "temperature" "${DEVICE[TEMPERATURE]}"
check_required_file "fan mode" "${DEVICE[FAN_MODE]}"
check_required_file "fan speed" "${DEVICE[FAN_SPEED]}"

current_temp="$(get_current_temperature)"
echo '0' > ${DEVICE[FAN_MODE]}
${FAN_LED} && led setup
current_fan_speed=$(cat ${DEVICE[FAN_SPEED]})
fan_active_until=0
while : ; do
	current_temp="$(get_current_temperature)"
	${FAN_DEBUG} && log "event: read_temp ${current_temp}°C"
	
	if [[ ${current_temp} -ge ${CONFIG[MAX_TEMP]} ]]; then
		# set fan speed to max if we are above the 'high' temperature
		new_fan_speed="${CONFIG[MAX_SPEED]}"
	elif [[ ${current_temp} -lt ${CONFIG[MIN_TEMP]} ]]; then
		# turn fan off if we are below the 'low' temperature
		new_fan_speed="1"
	else
		# dynamically set fan speed if we are between min and max temperature
		new_fan_speed="$(bc <<< "scale=2;((${CONFIG[MAX_SPEED]}-${CONFIG[MIN_SPEED]})/100*(100/(${CONFIG[MAX_TEMP]}-${CONFIG[MIN_TEMP]})*(${current_temp}-${CONFIG[MIN_TEMP]})))+${CONFIG[MIN_SPEED]}" | cut -d. -f1)"
	fi
	set_fan_speed "${new_fan_speed}"
	sleep ${CONFIG[CHECK_INTERVAL]} 
done


