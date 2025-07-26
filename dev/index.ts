import { Domain, Volume } from '@pulumi/libvirt';
import { getStack } from '@pulumi/pulumi';

const name = getStack();

const iso = new Volume('iso', {
  name: 'nixos',
  source: '../result/iso/nixos.iso',
});

const os = new Volume('os', {
  name: 'os',
  size: 10 * Math.pow(1024, 3), // 10Gb
});

const domain = new Domain(name, {
  name,
  autostart: true,
  disks: [
    {
      volumeId: iso.volumeId,
    },
    {
      volumeId: os.volumeId,
    }
  ],
});
