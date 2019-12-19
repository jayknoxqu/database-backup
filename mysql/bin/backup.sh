#!/bin/bash
# ==============================================================================
# Author        : Jayknoxqu
# Email         : jayknoxqu@gmail.com
# Date          : 2019.12.18
# Version       : 1.0.0
# Description   : This script is backup mysql databases and upload to aliyun oss
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
# 索引文件目录
index_dir=$program_dir/index

# 读取配置文件中的所有变量值, 设置为全局变量
conf_file="$program_dir/conf/backup.conf"
# mysql 用户
username=$(sed '/^username\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mysql 密码
password=$(sed '/^password\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mysql 备份目录
backup_dir=$(sed '/^backup_dir\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mysql 备份压缩打包目录
gzip_dir=$(sed '/^gzip_dir\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# percona-xtrabackup命令xtrabackup路径
xtrabackup_bin=$(sed '/^xtrabackup_bin\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 全备是在一周的第几天
full_backup_week_day=$(sed '/^full_backup_week_day\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mysql 全备前缀标识
full_backup_prefix=$(sed '/^full_backup_prefix\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# mysql 增量备前缀标识
increment_prefix=$(sed '/^increment_prefix\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 备份错误日志文件
error_log=$logs_dir/$(sed '/^error_log\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 备份索引文件
index_file=$index_dir/$(sed '/^index_file\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)

# 阿里云OSS Bucket
oss_bucket=$(sed '/^oss_bucket\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 自定义一个命名空间
oos_namespaces=$(sed '/^oos_namespaces\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 阿里云OSS Endpoint
oss_endpoint=$(sed '/^oss_endpoint\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 阿里云OSS AccessKeyId
oss_accesskeyid=$(sed '/^oss_accesskeyid\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 阿里云OSS AccessKeySecret
oss_accesskeysecret=$(sed '/^oss_accesskeysecret\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)
# 阿里云ossutil命令路径
ossutil_bin=$(sed '/^ossutil_bin\(\|\s\+\)=/!d;s/.*=\(\|\s\+\)//' $conf_file)

# 创建相关文件
mkdir -p $logs_dir $index_dir $gzip_dir $backup_dir

# 全量备份
function full_backup() {
  backup_name=${full_backup_prefix}_${backup_date}_${backup_time}_${backup_week_day}
  mkdir -p $backup_dir/${backup_name}
  $xtrabackup_bin \
    --user=$username \
    --password=$password \
    --backup \
    --target-dir=$backup_dir/${backup_name} >$logs_dir/${backup_name}_backup.log 2>&1
  return $?
}

# 增量备份
function increment_backup() {
  backup_name=${increment_prefix}_${backup_date}_${backup_time}_${backup_week_day}
  incr_base_name=$(sed -n '$p' $index_file |
    awk -F '[, {}]*' '{print $3}' |
    awk -F ':' '{print $2}')
  mkdir -p $backup_dir/${backup_name}
  $xtrabackup_bin \
    --user=$username \
    --password=$password \
    --backup \
    --target-dir=$backup_dir/${backup_name} \
    --incremental-basedir=$backup_dir/$incr_base_name >$logs_dir/${backup_name}_backup.log 2>&1
  return $?
}

# 发送备份到远程
function send_backup_to_remote() {
  backup_name=${1}_${backup_date}_${backup_time}_${backup_week_day}

  $ossutil_bin \
    cp $gzip_dir/${backup_name}.tar.bz2 \
    oss://$oss_bucket/$oos_namespaces/mysql/archives/${backup_name}.tar.bz2 \
    -f -e $oss_endpoint -i $oss_accesskeyid -k $oss_accesskeysecret \
    >$logs_dir/${backup_name}_upload.log 2>&1

}

# 删除之前的备份(一般在全备完成后使用)
function delete_before_backup() {
  awk <$index_file -F '[, {}]*' '{print $3}' |
    awk -v backup_dir=$backup_dir -F ':' '{if($2!=""){printf("rm -rf %s/%s\n", backup_dir, $2)}}' |
    /bin/bash

  awk <$index_file -F '[, {}]*' '{print $3}' |
    awk -v gzip_dir=$gzip_dir -F ':' '{if($2!=""){printf("rm -rf %s/%s.tar.bz2\n", gzip_dir, $2)}}' |
    /bin/bash

  awk <$index_file -F '[, {}]*' '{print $3}' |
    awk -v logs_dir=$logs_dir -F ':' '{if($2!=""){printf("rm -rf %s/%s_*.log\n", logs_dir, $2)}}' |
    /bin/bash
}

# 备份索引文件
function backup_index_file() {
  cp $index_file ${index_file}_"$(date -d "1 day ago" +%F)"
}

# 备份索引文件
function send_index_file_to_remote() {
  index_name=$(basename ${index_file})_$(date -d "1 day ago" +%F)
  backup_name=${full_backup_prefix}_${backup_date}_${backup_time}_${backup_week_day}

  $ossutil_bin \
    cp $index_file \
    oss://$oss_bucket/$oos_namespaces/mysql/indexs/${index_name} \
    -f -e $oss_endpoint -i $oss_accesskeyid -k $oss_accesskeysecret \
    >$logs_dir/${backup_name}_index.log 2>&1

}

# 添加索引, 索引记录了当前最新的备份
function append_index_to_file() {
  echo "{week_day:$backup_week_day, \
         dir:${1}_${backup_date}_${backup_time}_${backup_week_day}, \
         type:${1}, \
         date:${backup_date}}" >>$index_file
}

# 记录错误消息到文件
function logging_backup_err() {
  echo "{week_day:$backup_week_day, \
         dir:${1}_${backup_date}_${backup_time}_${backup_week_day}, \
         type:${1}, \
         date:${backup_date}}" >>$error_log
}

# 清空索引
function purge_index_from_file() {
  : >$index_file
}

# 清空错误日志信息
function purge_err_log() {
  : >$error_log
}

# 打包备份
function tar_backup_file() {
  cd $backup_dir || exit
  tar -jcf ${gzip_dir}/${1}_${backup_date}_${backup_time}_${backup_week_day}.tar.bz2 \
    ${1}_${backup_date}_${backup_time}_${backup_week_day}
  cd - >/dev/null || exit
}

# 判断是应该全备还是增量备份
# 0:full, 1:incr
function get_backup_type() {
  backup_type=0
  if [ "$full_backup_week_day" -eq "$(date +%u)" ]; then
    backup_type=0
  else
    backup_type=1
  fi
  touch $index_file
  if [ -z "$(cat $index_file)" ]; then
    backup_type=0
  fi
  return $backup_type
}

# 测试配置文件正确性
function test_conf_file() {
  # verify mysql-config
  if [ -z "$username" ]; then
    echo 'fail: configure file username not set'
    exit 2
  fi
  if [ -z "$password" ]; then
    echo 'fail: configure file password not set'
    exit 2
  fi
  if [ -z "$backup_dir" ]; then
    echo 'fail: configure file backup_dir not set'
    exit 2
  fi
  if [ -z "$gzip_dir" ]; then
    echo 'fail: configure file backup_dir not set'
    exit 2
  fi
  if [ -z "$full_backup_week_day" ]; then
    echo 'fail: configure file full_backup_week_day not set'
    exit 2
  fi
  if [ -z "$full_backup_prefix" ]; then
    echo 'fail: configure file full_backup_prefix not set'
    exit 2
  fi
  if [ -z "$increment_prefix" ]; then
    echo 'fail: configure file increment_prefix not set'
    exit 2
  fi
  if [ -z "$error_log" ]; then
    echo 'fail: configure file error_log not set'
    exit 2
  fi
  if [ -z "$index_file" ]; then
    echo 'fail: configure file index_file not set'
    exit 2
  fi

  # verify oss-config
  if [ -z "$oss_bucket" ]; then
    echo 'fail: configure file oss_bucket not set'
    exit 2
  fi
  if [ -z "$oos_namespaces" ]; then
    echo 'fail: configure file oos_namespaces not set'
    exit 2
  fi
  if [ -z "$oss_endpoint" ]; then
    echo 'fail: configure file oss_endpoint not set'
    exit 2
  fi
  if [ -z "$oss_accesskeyid" ]; then
    echo 'fail: configure file oss_accesskeyid not set'
    exit 2
  fi
  if [ -z "$oss_accesskeysecret" ]; then
    echo 'fail: configure file oss_accesskeysecret not set'
    exit 2
  fi
  if [ -z "$ossutil_bin" ]; then
    echo 'fail: configure file ossutil_bin not set'
    exit 2
  fi
}

# 执行
function main() {
  # 检测配置文件值
  test_conf_file
  # 判断是执行全备还是增量备份
  get_backup_type
  backup_type=$?
  case $backup_type in
  0)
    # 全量备份
    full_backup
    backup_ok=$?
    if [ 0 -eq "$backup_ok" ]; then
      ### 全备成功
      # 打包最新备份
      tar_backup_file $full_backup_prefix
      # 将tar备份发送到远程
      send_backup_to_remote $full_backup_prefix
      # 备份索引文件
      backup_index_file
      # 发送索引文件到远程
      send_index_file_to_remote
      # 清除之前的备份
      delete_before_backup
      # 清除索引文件
      purge_index_from_file
      # 添加索引, 索引记录了当前最新的备份
      append_index_to_file $full_backup_prefix
    else
      # 全备失败
      # 删除备份目录
      rm -rf ${backup_dir}/${full_backup_prefix}_${backup_date}_${backup_time}_${backup_week_day}
      # 记录错误日志
      logging_backup_err $full_backup_prefix
    fi
    ;;
  1)
    # 增量备份
    increment_backup
    backup_ok=$?
    if [ "$backup_ok" -eq 0 ]; then
      ### 增量备份成功
      # 打包最新备份
      tar_backup_file $increment_prefix
      # 将tar备份发送到远程
      send_backup_to_remote $increment_prefix
      # 添加索引, 索引记录了当前最新的备份
      append_index_to_file $increment_prefix
    else
      ### 增量备份失败
      # 删除备份目录
      rm -rf ${backup_dir}/${increment_prefix}_${backup_date}_${backup_time}_${backup_week_day}
      # 记录错误日志
      logging_backup_err $increment_prefix
    fi
    ;;
  esac
}

main
