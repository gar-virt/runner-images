# Runner Images

Recipes for generating runner images for Gitea Actions and [gar-virt](https://github.com/gar-virt/gar-virt) autoscaling.

## Prerequisites

* Linux (tested Ubuntu 24.04, AMD64)
* APT packages: `genisoimage make qemu-system`
* Wine (tested 11.0) is used for preparing Windows dependencies.
* Add yourself to the `kvm` group: `usermod -aG kvm "${USER}"` and log out/in as QEMU/KVM will be invoked.
* 2 GiB of free memory is sufficient for building virtual machine images sequentially.
* 50 GiB free disk space is sufficient for building all of the Docker images and virtual machine images.

## Building Docker Images

These images should be used by the Gitea Runner inside of a virtual machine.

```sh
cd docker-images
make [target]
```

If you have plenty of free system resources for building Docker images in parallel then you can do so with `make "-j<N>" [target] [options]` where `N` is the number of parallel jobs. Note that parallel builds with interleaving log output are harder to debug.

Refer to `./docker-images/Makefile` for the full list of supported options.

| Target            | Description                                         |
| ----------------- | --------------------------------------------------- |
| `build`           | Builds all of the supported Docker images.          |
| `publish`         | Publish all of the supported Docker images.         |
| `build-<image>`   | Build `image` Docker image.                         |
| `publish-<image>` | Publish `image` Docker image.                       |

The `image` names should match the names of the subdirectories of `./docker-images/`.

Omitting a target runs the `build` target which builds all of the supported Docker images.

When publishing an image, add the `TAG=[...]` option to the `make` command with your own Docker image tag including the Docker registry:

```sh
make publish TAG=docker.yourdomain.local/runner-images
```

## Building Virtual Machine Images

### Configuration

Copy the `./virtual-machines/res/<linux|windows>/config.json.sample` to the same directory with the name `config.json` and modify it.

The following table describes the config file for Linux.

| Property             | Description                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| `adminUserName`      | Name of the local admin account.                                                                  |
| `sshPublicKey`       | An SSH public key for managing the virtual machine. An admin can use it for troubleshooting.      |
| `dockerTag`          | Runner Docker image tag. Used for pulling your runner images during VM setup.                     |

The following table describes the config file for Windows.

| Property             | Description                                                                                                |
| -------------------- | ---------------------------------------------------------------------------------------------------------- |
| `adminUserName`      | Name of the local admin account.                                                                  |
| `sshPublicKey`       | An SSH public key for managing the virtual machine. An admin can use it for troubleshooting.               |
| `activationEdition`  | The Windows edition to upgrade to. See the output of `DISM /Online /Get-TargetEditions` for valid options. |
| `activationKey`      | Windows activation key. It's expected that a GLVK will be used. The sample key is a public GLVK.           |
| `activationServer`   | The hostname of the activation server.                                                                     |
| `activationServerIp` | The IP address to map the hostname to in the local `hosts` file.                                           |

### Building

The base images produced are meant to be used by gar-virt to create ephemeral virtual machines.

```sh
cd virtual-machines
make [target] [options]
```

If you have plenty of free system resources for building virtual machine images in parallel then you can do so with `make "-j<N>" [target] [options]` where `N` is the number of parallel jobs. Note that parallel builds with interleaving log output are harder to debug.

Refer to `./virtual-machines/Makefile` for the full list of supported options.

| Target         | Description                                               |
| -------------- | --------------------------------------------------------- |
| `<image>-deps` | Fetch dependencies.                                       |
| `<image>-seed` | Build seed image.                                         |
| `<image>-base` | Build base image.                                         |
| `<image>-test` | Start a fresh virtual machine for testing the base image. |

The `image` names should match the names of the subdirectories of `./virtual-machines/`.

Omitting a target runs the `all` target which builds all of the supported base images.

If the build goes smoothly then the virtual machines should shut down at the end of the process.

Find the built images in `./build/<image>/base/`.

### Troubleshooting

It may be necessary to log into virtual machines in order to investigate build failures.

You can enable SSH forwarding for virtual machines by adding the options `SSH_FORWARD=1` and optionally `SSH_FORWARD_PORT=<LOCAL_SSH_PORT>` (port `2222` by default) to the `make` command:

```sh
ssh -i SSH_PRIVATE_KEY_PATH -p LOCAL_SSH_PORT USER@127.0.0.1
```

`SSH_PRIVATE_KEY_PATH` is the private key that matches the `sshPublicKey` in your config file.

Match the `LOCAL_SSH_PORT` with the one used with `SSH_FORWARD_PORT`.

The `USER` will be whatever you configured as `adminUserName` in your config file.

Fill out the placeholders.

#### Linux Notes

Log in with SSH and see the [cloud-init log files](https://docs.cloud-init.io/en/latest/reference/user_files.html).

If something went wrong before SSH was set up, you can check the cloud-init output in the QEMU window. Local login is disabled early.

#### Windows Notes

Log in with SSH and monitor the log file produced by the post-install script:

```ps1
Get-Content -Path C:\Windows\Setup\Scripts\post_install.log -Wait
```

Give some time for the SSH server to work after the Windows setup completes.

If something went wrong before SSH was set up, you can log in locally. Local login is disabled after SSH is set up.
