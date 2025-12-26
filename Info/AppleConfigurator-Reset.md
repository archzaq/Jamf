# Description
The following steps are used to hard restore an Apple Silicon macOS device (M1+ or newer) using another macOS device. This process can be used to upgrade or downgrade the Target (broken) macOS device.

# Requirements
### Downloads for Rescue Mac
1. Apple Configurator
	- Apple Configurator can be installed from [Self Service](jamfselfservice://content?entity=app&id=25&action=view) or from the [App Store](https://apps.apple.com/us/app/apple-configurator/id1037126344?mt=12)
2. [DFU Blaster](https://twocanoes.com/products/mac/dfu-blaster/)
3. [IPSW file](https://ipsw.me) for the specific macOS hardware model
	- Example: M2 MacBook Air
		1. On ipsw.me choose "Mac", scroll down until you see "MacBook Air (M2, 2022)"
		2. Choose the desired macOS version IPSW file
### Cable
1. USB-C to USB-C data cable
	- Connect this cable to the [DFU port](https://support.apple.com/en-us/120694) of each device

# Reset Process
1. Open Apple Configurator
2. Open DFU Blaster
3. In DFU Blaster, select "DFU Mode"
	- If your USB-C to USB-C cable is connected properly, the Target Mac's screen will go black and you will see a square saying "DFU" in Apple Configurator
		- If not, see [Troubleshooting](#Troubleshooting)
4. Drag the downloaded IPSW file to the "DFU" icon in Apple Configurator, then select "Restore"
5. Watch the process as it installs, you may be asked multiple times to "Allow" the Rescue Mac to communicate with the Target Mac
	- If you miss one of these prompts, or wait too long to answer, the process will fail
6. Once the process is completed, you will be at the macOS Setup Assistant. Continue through the Setup Assistant and you will be guided through the assigned PreStage Enrollment

# Troubleshooting
### Apple Configurator Issues
Unable to see any connected devices
#### Possible Solutions:
1. Reboot Rescue Mac
2. If possible, disconnect the devices, log into Target Mac, connect the cable and "Allow" the connection
3. Try another USB-C to USB-C cable
4. Delete and reinstall Apple Configurator
5. Manually put the device in [DFU mode](https://support.apple.com/en-us/108900)
	1. With the Target Mac on, press and hold the power button for 10 seconds to turn it off
	2. Immediately hold down Left Control, Left Option, Right Shift, and the Power button for 10 seconds
	3. Release all buttons except the Power button, hold for about 10 seconds
		- You should see the Target Mac's screen will go black and you will see a square saying "DFU Mode" in Apple Configurator on the Rescue Mac
6. Update the Rescue Mac's OS
### DFU Blaster Issues
Unable to put device in DFU mode
#### Possible Solutions:
1. Read the following [article](https://support.apple.com/en-us/120694) and ensure both devices are connected to the proper DFU port
	- If both devices are connected properly and the Rescue Mac is updated, try another USB-C to USB-C data cable
2. Ensure you have the proper IPSW file for the Target Mac's specific model
3. Try another [DFU Blaster version](https://twocanoes.com/products/mac/dfu-blaster/history/)
4. Manually put the device in [DFU mode](https://support.apple.com/en-us/108900)
	1. With the Target Mac on, press and hold the power button for 10 seconds to turn it off
	2. Immediately hold down Left Control, Left Option, Right Shift, and the Power button for 10 seconds
	3. Release all buttons except the Power button, hold for about 10 seconds
		- You should see the Target screen will go black and you will see a square saying "DFU Mode" in Apple Configurator on the Rescue Mac
