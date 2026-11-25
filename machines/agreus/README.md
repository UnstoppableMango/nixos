# agreus

## Measurements

- A generation costs roughly 37M of kernel plus initrd, so 8 fit in the 500M ESP.
  25 overflowed it and blocked rebuilds, since systemd-boot writes the new entry before pruning the old ones.
