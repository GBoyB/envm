# envm
Easy Node Version Manager


## Installation
```shell
wget -O- http://github.hzspeed.cn/envm/install.sh | bash
```
PS: 内网环境或者代理环境可在执行上述命令前增加执行, 使用wget获取文件
```
export METHOD=script
```
手动source rc文件或重新打开sh,即可启动。

如果遇到 ssl 证书问题， 尝试`wget`加上选项`--no-check-certificate`



## Usage
Support `easynode`,``alinode`, `node`, `iojs`, `node-profiler` version manager

`envm lookup` 查看 `easynode` 基于 `node` 的版本, 便于替换相应版本。

Example install alinode:
 * envm ls-remote easynode
 * envm lookup
 * envm install easynode-v7.0.0-pre
 * envm use easynode-v7.0.0-pre

Example install node:
 * envm install node-v4.2.1
 * envm use node-v4.2.1

Example install node-profiler:
 * envm install profiler-v0.12.6
 * envm use profiler-v0.12.6

More:
 * refer to `envm help`

Note:
  * to remove, delete, or uninstall envm - just remove ~/.envm folders


## License

envm is released under the MIT license.
