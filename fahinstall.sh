#!/bin/bash -e
#FAH Install script
# 3/16/2013 - created

trap "echo Premature exit." EXIT

if [ "$(id -ru)" != "0" ]; then
	echo ERROR: need root privileges. Run with sudo.
	trap - EXIT
	exit 1
fi

if [ -z "$SUDO_USER" ]; then
	echo ERROR: SUDO_USER variable not set, cannot continue.
	trap - EXIT
	exit 1
fi

if [ "$SUDO_USER" = "fah" ]; then
	echo ERROR: user \'fah\' not supported. Create another user and try again.
	trap - EXIT
	exit 1
fi

TARGET=$(eval echo ~$SUDO_USER/fah)

if [ "$1" = "-f" ]; then
	umount $TARGET || true
	rm -r $TARGET
fi

if [ -e "$TARGET" ]; then
	echo ERROR: $TARGET already exists. Use -f to force installation.
	trap - EXIT
	exit 1
fi
	
#12.04 tweaks
echo ==== Applying 12.04 tweaks...
update-rc.d ondemand disable
sed -i -e 's/^ENABLED.*$/ENABLED="0"/' /etc/default/irqbalance
echo kernel.randomize_va_space=0 > /etc/sysctl.d/99-fah.conf
echo kernel.panic=3600 >> /etc/sysctl.d/99-fah.conf
echo kernel.print-fatal-signals=1 >> /etc/sysctl.d/99-fah.conf

#create fah directory
echo ==== Creating fah directory...
sudo -u $SUDO_USER mkdir $TARGET

#update fstab and mount tmpfs
echo ==== Setting up tmpfs...
grep -v $TARGET /etc/fstab > /tmp/fstab-$SUDO_USER.$$
echo "tmpfs  $TARGET  tmpfs  rw,uid=$(id -u $SUDO_USER),gid=$(id -g $SUDO_USER)  0  0" >> /tmp/fstab-$SUDO_USER.$$
mv /tmp/fstab-$SUDO_USER.$$ /etc/fstab
sync
mount -a

#get restore and backup scripts
echo ==== Setting up backup and restore scripts...
cd /usr/bin
rm -f fahbackup fahrestore
wget -nv http://darkswarm.org/fahtools/fahbackup http://darkswarm.org/fahtools/fahrestore
chmod +x fahbackup fahrestore

#update rc.local with fahrestore
echo ==== Updating rc.local...
(head -1 /etc/rc.local ; echo "sudo -u $SUDO_USER fahrestore #[H]ardOCP" ; tail -n +2 /etc/rc.local | grep -v '#\[H]ardOCP') > /tmp/rclocal-$SUDO_USER.$$
mv /tmp/rclocal-$SUDO_USER.$$ /etc/rc.local
chmod +x /etc/rc.local

#create backup script in /etc/init.d and symlinks
echo ==== Setting up shutdown scripts...
echo "#!/bin/bash" > /etc/init.d/fahbackup-rc
echo "sudo -u $SUDO_USER fahbackup" >> /etc/init.d/fahbackup-rc
chmod +x /etc/init.d/fahbackup-rc
ln -fs /etc/init.d/fahbackup-rc /etc/rc0.d/K10fahbackup-rc
ln -fs /etc/init.d/fahbackup-rc /etc/rc1.d/K10fahbackup-rc
ln -fs /etc/init.d/fahbackup-rc /etc/rc6.d/K10fahbackup-rc

#set up cron job
echo ==== Setting up cron job...
(sudo -u $SUDO_USER crontab -l 2> /dev/null | grep -v fahbackup || true) > /tmp/cron-$SUDO_USER.$$
echo "00 * * * * fahbackup > /dev/null 2>&1"  >> /tmp/cron-$SUDO_USER.$$
crontab -u $SUDO_USER /tmp/cron-$SUDO_USER.$$
rm /tmp/cron-$SUDO_USER.$$


#get fah files
echo ==== Downloading F@H files...
cd $TARGET
echo "====      client"
wget -nv "http://www.stanford.edu/group/pandegroup/folding/release/FAH6.34-Linux64-SMP.exe"
mv FAH6.34-Linux64-SMP.exe fah6
chmod +x fah6
for i in a3 a4 a5 ; do
	echo "====     FahCore_$i"
	wget -nv -O - http://www.stanford.edu/~pande/Linux/AMD64/beta/Core_$i.fah | dd skip=1 status=noxfer | bzip2 -cd > FahCore_$i.exe
	echo
done
chmod +x FahCore*
chown -R $SUDO_USER:$(id -g $SUDO_USER) .

#install software
echo ==== Installing required software...
apt-get install -qq openssh-server screen samba mcelog pastebinit build-essential

#install thekraken
echo ==== Installing thekraken...
rm -fr /tmp/thekraken-$SUDO_USER.$$
mkdir /tmp/thekraken-$SUDO_USER.$$
cd /tmp/thekraken-$SUDO_USER.$$
wget -nv http://darkswarm.org/thekraken/thekraken-current.tar.gz
mkdir src
cd src
tar xzf ../thekraken*
cd thekraken*
make
make install
rm -r /tmp/thekraken-$SUDO_USER.$$

#wrap cores
echo ==== Wrapping cores...
cd $TARGET
sudo -u $SUDO_USER thekraken -i

#run configonly
echo ==== Running F@H config...
sudo -u $SUDO_USER ./fah6 -configonly || true
echo

#set up user share
echo ==== Setting up samba...
sudo -u $SUDO_USER net usershare add fah $TARGET "" "Everyone:f" "guest_ok=y"

#update smb.conf - security = share (no p/w required to connect)
cp -a /etc/samba/smb.conf /etc/samba/smb.conf-horde-$(date +%s).$$
testparm -s | grep -v '^\tsecurity =' | sed -e 's/\[global]/&\n\tsecurity = share/' > /tmp/smbconf-$SUDO_USER.$$
mv /tmp/smbconf-$SUDO_USER.$$ /etc/samba/smb.conf

echo
echo Your IP Address: $(ip route get 8.8.8.8 | sed -ne '{s/^.*src.//;p;q}')
echo Your machine name: $HOSTNAME
echo
echo Done. Please reboot your system now.

trap - EXIT
