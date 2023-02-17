/sbin/init
systemctl restart autofs
ps -ef

echo "hello entrypoint"

# run the command given as arguments from CMD
exec "$@"
