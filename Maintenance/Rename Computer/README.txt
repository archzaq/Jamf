ComputerRename.sh
  If the current device name contains "Mac", rename it using the SLU standard.
  If the current device name already contains two hyphens, rename it using the pre-existing prefix and the final six characters of the serial number, exiting if the name is already correct.
  If the current device name already contains a hyphen, rename it using the pre-existing prefix and the final six characters of the serial number, exiting if the name is already correct.
  If the current device name fails to match any conditions, rename it using the SLU standard.

ComputerRename_Menu.sh
  If the current device name contains "Mac", prompt the user to choose their department prefix.
  If the current device name already contains two hyphens, prompt the user if they want to choose a new prefix, if so, prompt the user to choose their department prefix.
  If the current device name already contains a hyphen, prompt the user if they want to choose a new prefix, if so, prompt the user to choose their department prefix.
  If the current device name fails to match any conditions, prompt the user to choose their department prefix.
