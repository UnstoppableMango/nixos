# This expression was written by `cbrauchli` at https://discourse.nixos.org/t/disable-suspend-if-ssh-sessions-are-active/11655/4
# with minor modifications by Dominic Mayhew
#
# ... and now UnstoppableMango

{
  config,
  lib,
  pkgs,
  ...
}:

let
  RUN_DIR = "/run/ssh-sleep-block";
  PID_PATH = "${RUN_DIR}/pid";
  PID_PIPE = "${RUN_DIR}/pid_pipe";
  LOCK_PATH = "${RUN_DIR}/lock";

  # Prevent sleeping on active SSH
  sleep_script = pkgs.writeScript "infinite-sleep" ''
    #!/bin/sh

    echo $$ >${PID_PATH}
    echo $$ >${PID_PIPE}
    sleep infinity
  '';

  inhibit_script = pkgs.writeScript "inhibit_script" ''
    #!/bin/sh

    systemd-inhibit --what=sleep --why="Active SSH session" --mode=block ${sleep_script} 0>&- &> ${RUN_DIR}/inhibit.out &
  '';

  ssh_script = pkgs.writeScript "ssh-session-handler" ''
    #!/bin/sh
    #
    # This script runs when an ssh session opens/closes, and masks/unmasks
    # systemd sleep and hibernate targets, respectively.
    #
    # Inspired by: https://unix.stackexchange.com/a/136552/84197 and
    #              https://askubuntu.com/a/954943/388360

    (
      if ! ${pkgs.util-linux}/bin/flock -w 10 200; then
          logger "Failed to acquire ssh sleep inhibitor lock"
          exit 1
      fi

      num_ssh=$(${pkgs.iproute2}/bin/ss -nt | awk '$1 == "ESTAB" && $4 ~ /:22$/' | wc -l)

      case "$PAM_TYPE" in
          open_session)
              if [ "$num_ssh" -gt 1 ]; then
                  exit
              fi

              logger "Starting sleep inhibitor"

              old_umask=$(umask)
              umask 077
              rm -f ${PID_PIPE}
              if ! mkfifo ${PID_PIPE}; then
                  logger "Failed to create PID FIFO at ${PID_PIPE}"
                  umask "$old_umask"
                  exit 1
              fi
              umask "$old_umask"

              ${inhibit_script}
              logger "Sleep inhibitor started with PID $(cat ${PID_PIPE})"
              rm -f ${PID_PIPE}
              ;;

          close_session)
              if [ "$num_ssh" -ne 0 ]; then
                  exit
              fi

              if [ ! -f ${PID_PATH} ]; then
                  exit
              fi

              logger "Killing sleep inhibitor PID $(cat ${PID_PATH})"
              kill -9 $(cat ${PID_PATH}) && rm -f ${PID_PATH}
              ;;

          *)
              exit
      esac
    ) 200>${LOCK_PATH}

  '';
in
{
  options.ssh.inhibitSleepOnSsh.enable = lib.mkEnableOption "blocking system sleep while an SSH session is active";

  config = lib.mkIf config.ssh.inhibitSleepOnSsh.enable {
    systemd.tmpfiles.rules = [
      "d ${RUN_DIR} 0700 root root -"
    ];

    security.pam.services.sshd.text = pkgs.lib.mkDefault (
      pkgs.lib.mkAfter "# Prevent sleep on active SSH\nsession optional pam_exec.so quiet ${ssh_script}"
    );
  };
}
