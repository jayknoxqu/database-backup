#!/bin/bash
# ==============================================================================
# Author        : Jayknoxqu
# Email         : jayknoxqu@gmail.com
# Date          : 2019.12.18
# Version       : 1.0.0
# Description   : This script is backup mongodb databases
# ==============================================================================

# 备份日期
backup_date=$(date +%F)
# 备份时间
backup_time=$(date +%H-%M-%S)
# 备份时的周几
backup_week_day=$(date +%u)

# 获得程序路径名
program_dir=$(dirname $0)/..
# 日志文件目录
logs_dir=$program_dir/logs

# 读取配置文件中的所有变量值, 设置为全局变量
conf_file="$program_dir/conf/backup.conf"
# mongodb IP地址或域名
host=$(sed '/^host\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mongodb 端口号
port=$(sed '/^port\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mongodb 用户
username=$(sed '/^username\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mongodb 密码
password=$(sed '/^password\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mongodump 附加参数
params=$(sed '/^params\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mongo 备份目录
backup_dir=$(sed '/^backup_dir\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 备份文件保留天数
retain_days=$(sed '/^retain_days\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mongodump命令路径
mongodump_bin=$(sed '/^mongodump_bin\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)

# mongo 全备前缀标识
full_backup_prefix=$(sed '/^full_backup_prefix\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 备份错误日志文件
error_log=$logs_dir/$(sed '/^error_log\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)

# 创建相关文件
mkdir -p $logs_dir $backup_dir

# 全量备份
function full_backup() {
  backup_name=${full_backup_prefix}_${backup_date}_${backup_time}_${backup_week_day}

  $mongodump_bin \
    --host $host --port $port --username $username --password $password \
    --gzip $params --archive >$backup_dir/$backup_name.archive.gz \
    2>$logs_dir/${backup_name}.log

  return $?
}

# 删除之前的备份(一般在全备完成后使用)
function delete_before_backup() {

  # 删除 3 天前的备份日志
  find $logs_dir -name '*.log' -mtime +$retain_days -delete

  # 删除 3 天前的备份文件
  find $backup_dir -name '*.archive.gz' -mtime +$retain_days -delete

}

# 记录错误消息到文件
function logging_backup_err() {
  echo "{week_day:$backup_week_day, \
         dir:${1}_${backup_date}_${backup_time}_${backup_week_day}, \
         type:${1}, \
         date:${backup_date}}" >>$error_log
}

# 清空错误日志信息
function purge_err_log() {
  : >$error_log
}

# 发送备份到远程
function send_backup_to_remote() {
  echo "send $1 remote ok"
}

# 测试配置文件正确性
function test_conf_file() {
  # 判断每个变量是否在配置文件中有配置，没有则退出程序
  if [ -z "$host" ]; then
    echo 'fail: configure file host not set'
    exit 2
  fi
  if [ -z "$port" ]; then
    echo 'fail: configure file port not set'
    exit 2
  fi
  if [ -z "$username" ]; then
    echo 'fail: configure file username not set'
    exit 2
  fi
  if [ -z "$password" ]; then
    echo 'fail: configure file password not set'
    exit 2
  fi
  if [ -z "$full_backup_prefix" ]; then
    echo 'fail: configure file full_backup_prefix not set'
    exit 2
  fi
  if [ -z "$error_log" ]; then
    echo 'fail: configure file error_log not set'
    exit 2
  fi
  if [ -z "$backup_dir" ]; then
    echo 'fail: configure file backup_dir not set'
    exit 2
  fi
  if [ -z "$retain_days" ]; then
    echo 'fail: configure file retain_days not set'
    exit 2
  fi
  if [ -z "$mongodump_bin" ]; then
    echo 'fail: configure file mongodump_bin not set'
    exit 2
  fi

}

# 执行
function main() {
  # 检测配置文件值
  test_conf_file

  # 全量备份
  full_backup
  backup_ok=$?
  if [ 0 -eq "$backup_ok" ]; then
    # 全备成功,将tar备份发送到远程
    send_backup_to_remote $full_backup_prefix
    # 清除之前的备份
    delete_before_backup
  else
    # 全备失败,删除备份文件
    rm -f ${backup_dir}/${full_backup_prefix}_${backup_date}_${backup_time}_${backup_week_day}.archive.gz
    # 记录错误日志
    logging_backup_err $full_backup_prefix
  fi

}

main
