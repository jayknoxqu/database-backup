### 安装压缩工具

```bash
yum -y install bzip2
```



### 安装[percona-xtrabackup](https://www.percona.com/doc/percona-xtrabackup/LATEST/installation/yum_repo.html)

xtrabackup8 适用于 mysql8

```
sudo yum install https://repo.percona.com/yum/percona-release-latest.noarch.rpm

sudo percona-release enable-only tools

sudo yum install percona-xtrabackup-80
```





### 安装ossutil工具


```bash
# 下载并安装
curl -L http://gosspublic.alicdn.com/ossutil/1.6.9/ossutil64 -o /usr/local/bin/ossutil64

# 添加执行权限
chmod +x /usr/local/bin/ossutil64

#查看版本
ossutil64 -v
```



### 配置ossutil文件
在配置文件`conf/backup.conf`中添加ossutil信息
```
### oss-config
# 阿里云OSS Bucket
oss_bucket = test-data-backup
# 自定义一个命名空间
oos_namespaces = test
# 阿里云OSS Endpoint
oss_endpoint = oss-cn-shenzhen-internal.aliyuncs.com
# 阿里云OSS AccessKeyId
oss_accesskeyid = LTAI3Fm7GEQca5BTBK8Bhqea
# 阿里云OSS AccessKeySecret
oss_accesskeysecret = jCPQ2cgJz3ZfBoc3btdCn2uHgPDdcl
# 阿里云ossutil命令路径
ossutil_bin = /usr/local/bin/ossutil64
```
ossutil具体使用方法可查看[官方文档](https://help.aliyun.com/document_detail/50452.html)





### 使用方法



#### 克隆脚本到本地

```bash
git clone https://github.com/jayknoxqu/database-backup.git /usr/local/database-backup
```



#### 赋予脚本执行权限

```bash
chmod +x $(find /usr/local/database-backup -name '*.sh')
```



#### 使用`crontab -e`编辑定时任务

```
# 每天凌晨3点15分执行备份mongodb
15 3 * * * /usr/local/database-backup/mongo/bin/backup.sh >/dev/null 2>&1

# 每天凌晨4点15分执行备份mysql
15 4 * * * /usr/local/database-backup/mysql/bin/backup.sh >/dev/null 2>&1
```



### 恢复备份文件



##### （1）停止MySQL 服务

```sh
systemctl stop mysqld
```



##### （2）备份数据目录

```sh
mv /var/lib/mysql /var/lib/mysql-bak
```



##### （3）新建数据目录

```sh
mkdir -p /var/lib/mysql
```



##### （4）准备全量备份的数据

```shell
xtrabackup --prepare --apply-log-only --target-dir=/mnt/backups/mysql/full_2021-08-23_04-15-01_1
```
  Tip：参数`--defaults-file=/etc/my.cnf`可指定mysql的配置文件，它会读取mysql数据的目录和binlog目录



##### （5）合并增量备份的数据

```shll
xtrabackup --prepare --apply-log-only --target-dir=/mnt/backups/mysql/full_2021-08-23_04-15-01_1  --incremental-dir=/mnt/backups/mysql/incr_2021-08-24_04-15-01_2
```
  Tip：多份增量备份的数据重复执行合并操作即可



##### （6）准备合并之后的数据

```shell
xtrabackup --prepare --target-dir=/mnt/backups/mysql/full_2021-08-23_04-15-01_1
```



##### （7）恢复备份数据

```shell
xtrabackup --copy-back --target-dir=/mnt/backups/mysql/full_2021-08-23_04-15-01_1
```



##### （8） 赋予文件夹权限

```shell
 chown -R mysql:mysql /var/lib/mysql
```



##### （9） 启动数据库服务

```shell
systemctl start mysqld 或者 /usr/sbin/mysqld --user=mysql &
```
