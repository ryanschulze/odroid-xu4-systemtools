# odroid-xu4-systemtools
This repository has system tools I commonly deploy on my odroid XU4, mainly fan control (the script was inspired by [odroid-xu3-fan-control](https://github.com/nthx/odroid-xu3-fan-control)). The automatic settings by the system tend to run the fan pretty high (and the stock fan is has a really noisy high pitched sound). Other scripts I found didn't have configuration options for setting min/max fan speed or temperature ranges.

# Fan Control

Installation
-
The easiest way to deploy the script to an odroid device would be using ansible. There is an [example playbook](example_playbook.yml) included that shows how to change default settings. The simplest deployment using ansible would be `ansible-playbook example_playbook.yml --limit=<odroid IP>` (assuming ansible knows where your inventory file is).

If you don't want to use ansible, just copy the following files to the following destinations on your device, and the configuration example (from the "Configuration" block) to **/etc/default/odroid-fan-control**, [/etc/init.d/odroid-fan-control](roles/odroid/files/odroid-fan-control.sh), [/usr/local/sbin/odroid-fan-control](roles/odroid/files/odroid-fan-control.init)

Configration
-
The following settings can be changed in ansible (with the following defaults): 
```yaml
odroid_config_verbose:        'true'
odroid_config_debug:          'false'
odroid_config_led:            'false'
odroid_config_check_interval: 2
odroid_config_min_fan_active: 15
odroid_config_min_speed:      80
odroid_config_max_speed:      255
odroid_config_min_temp:       55
odroid_config_max_temp:       80
```
|option | description |
|---|---|
| odroid_config_verbose | Sends output to syslog |
| odroid_config_debug | Sends output to stdout |
| odroid_config_led | Turn the (blue) LED on when the fan is on |
| odroid_config_check_interval | How often to check the temperature |
| odroid_config_min_fan_active | How many seconds to leave the fan running after we fall below *odroid_config_min_temp* |
| odroid_config_min_speed | Minimum fan speed to use |
| odroid_config_max_speed | Maximum fan speed to use |
| odroid_config_min_temp | At which temperature should we turn the fan on |
| odroid_config_max_temp | At this temperature run the fan at *odroid_config_max_speed* |

An example of */etc/default/odroid-fan-control* with the default settings
```bash
## Default settings for odroid-fan-control. This file is sourced by /bin/sh from
# /etc/init.d/odroid-fan-control.
 
# Output status messages to syslog
FAN_VERBOSE=true
 
# Output status messages to stdout
FAN_DEBUG=false
 
# Turn on LED when fan is on
FAN_LED=false
 
# how often to check the temperature (in seconds)
CONFIG_CHECK_INTERVAL=2
 
# if fan turns on, leave it on for at least x seconds
CONFIG_MIN_FAN_ACTIVE=15
 
# minimum fan speed (when on)
CONFIG_MIN_SPEED=80
 
# maximum fan speed
CONFIG_MAX_SPEED=255

# temperature when we turn the fan on
CONFIG_MIN_TEMP=55

 # temperature where we hit maximum fan speed
CONFIG_MAX_TEMP=80
```

Usage
-
Just start the via the init script (`service odroid-fan-control start`). If no */etc/default/odroid-fan-control* file exists the defaults are used. If the script exits (or crashes) fan control is automatically reset to automatic mode.
