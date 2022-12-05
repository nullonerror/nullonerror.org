---
layout: post
title: >
  My cloud workspace
---

![kubectl](/public/2022-12-05-my-cloud-workspace/old-man-yells-at-cloud.jpg){: .center }

### Someone else's computer

Sometimes your development machine is not sufficient for various reasons: For example, you need to build an `x86_64` Docker image and do not want to pay the cost of *QEMU*, or it is on a limited internet; for these and other reasons, I created a terraform to bootstrap a development machine with a single command.

Of course, [Codespaces](https://github.com/features/codespaces) is the ideal solution for this. However, it does not exist in my region, and it is expensive.

My solution relies on the following:
* [Terraform](https://www.terraform.io/) for provisioning and de-provisioning.
* [Cloud-init](https://cloud-init.io/) for initial configuration.
* [Tailscale](https://tailscale.com/) to create a secure tunnel between the machine located in the cloud and my machine.
* [asdf](https://asdf-vm.com/) for installing languages and tools.

I have chosen [Vultr](https://vultr.com/) because they are cheap and have machines in my region.

During the setup, it gets configured the Tailscale and the SSH public keys fetched from GitHub, this allows connecting to the machine with a single command:

```shell
ssh vultr
```

This is possible because Tailscale  has a feature named [magic DNS](https://tailscale.com/kb/1081/magicdns/), which will add the hostname of each machine, by this way, you do not need to remember addresses or open ports, everything works out of the box.

It is also possible to use [VSCode remote development](https://code.visualstudio.com/docs/remote/ssh), which turns it a real game changer. 

### Costs

You only pay for the time while the cloud instance is running, to dispose of it, you just need to run:

```shell
terraform destroy
```

### Source Code

[github.com/skhaz/my-cloud-workspace](https://github.com/skhaz/my-cloud-workspace)
