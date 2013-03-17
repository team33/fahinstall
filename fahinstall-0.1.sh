#!/bin/bash
#FAH Install script
# 3/16/2013 - created

#root check
if [ "$(id -ru)" != "0" ]; then
  echo ERROR: need root privileges - run with sudo
  exit 1
fi

#12.04 tweaks
echo Applying 12.04 tweaks...
update-rc.d ondemand disable
sed -i -e 's/^ENABLED.*$/ENABLED="0"/' /etc/default/irqbalance
echo kernel.randomize_va_space=0 > /etc/sysctl.d/99-fah
echo kernel.panic=3600 >> /etc/sysctl.d/99-fah
echo kernel.print-fatal-signals=1 >> /etc/sysctl.d/99-fah

#create fah directory
echo Creating fah directory...
sudo -u $SUDO_USER mkdir /home/$SUDO_USER/fah

#update fstab and mount tmpfs
echo Setting up tmpfs...
echo "tmpfs  /home/$SUDO_USER/fah  tmpfs  rw,uid=$(id -u $SUDO_USER)  0  0" >> /etc/fstab
mount -a

#get restore and backup scripts
echo Getting backup and restore scripts...
cd /usr/bin
rm -f fahbackup
rm -f fahrestore
wget http://darkswarm.org/fahtools/fahbackup
wget http://darkswarm.org/fahtools/fahrestore
chmod +x fahbackup
chmod +x fahrestore

#update rc.local with fahrestore
echo Updating rc.local...
(head -1 /etc/rc.local ; echo "sudo -u $SUDO_USER fahrestore #[H]ardOCP" ; tail -n +2 /etc/rc.local | grep -v '#\[H]ardOCP') > /tmp/horde-$USER.$$ ; cp /tmp/horde-$USER.$$ /etc/rc.local

#create backup script in /etc/init.d and symlinks
echo Setting up shutdown scripts...
echo "#!/bin/bash" >> /etc/init.d/fahbackup-rc
echo "sudo -u $SUDO_USER fahbackup" >> /etc/init.d/fahbackup-rc
chmod +x /etc/init.d/fahbackup-rc
ln -s  /etc/init.d/fahbackup-rc /etc/rc0.d/K10fahbackup-rc
ln -s  /etc/init.d/fahbackup-rc /etc/rc1.d/K10fahbackup-rc
ln -s  /etc/init.d/fahbackup-rc /etc/rc6.d/K10fahbackup-rc

#set up cron job
echo Setting up cron job...
sudo -u $SUDO_USER crontab -l > /tmp/cron
echo "00 * * * * fahbackup"  >> /tmp/cron
crontab -u $SUDO_USER /tmp/cron
rm /tmp/cron


#get fah files
echo Downloading F@H files...
cd /home/$SUDO_USER/fah
wget "http://www.stanford.edu/group/pandegroup/folding/release/FAH6.34-Linux64-SMP.exe"
mv FAH6*.* fah6
chmod 755 fah6
for i in a3 a4 a5 ; do wget -O - http://www.stanford.edu/~pande/Linux/AMD64/beta/Core_$i.fah | dd skip=1 | bzip2 -cd > FahCore_$i.exe ; done
chown -R $SUDO_USER .

#install thekraken
echo Installing thekraken...
rm -r /tmp/install-$SUDO_USER.$$
mkdir /tmp/install-$SUDO_USER.$$
cd /tmp/install-$SUDO_USER.$$
wget http://darkswarm.org/thekraken/thekraken-current.tar.gz
tar xzf thekraken*.*
cd thekraken*
make
make install

#wrap cores
echo Wrapping cores...
cd /home/$SUDO_USER/fah
sudo -u $SUDO_USER thekraken -i

#run configonly
echo Running F@H config...
./fah6 -configonly

#install ssh and screen
echo Installing ssh and screen...
apt-get install -qq openssh-server
apt-get install -qq screen
