# Un-Enroll and Re-Enroll
#### Un-Enroll Command
```bash
sudo jamf removeFramework
```
#### Re-Enroll Methods
First try the profiles command. Re-Enrolling using this command is faster, easier, and is linked to PreStage Enrollment<br />
**NOTE:** If successful, you will receive a notification from macOS in the top right of the screen that you must accept
```bash
sudo profiles renew -type enrollment
```

If unsuccessful, you must enroll using the User-Initiated Enrollment link<br />
`https://EXAMPLE.jamfcloud.com/enroll`<br />
<br />
If you are unable to enroll using the normal User-Initiated Enrollment link, you can attempt the "Quick Add" link which connects to Jamf Pro using a PKG file<br />
`https://EXAMPLE.jamfcloud.com/enroll/?type=QuickAdd`<br />

