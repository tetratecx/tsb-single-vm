/sbin/init
systemctl restart autofs

echo "hello entrypoint"

# run the command given as arguments from CMD
exec "$@"
