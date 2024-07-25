#! /bin/bash

PACKAGE_DIR="/home/admin/aur_packages" # path to a "downloads" folder containing folders with 'makepkg' files
SRV_DIR="/srv/http/archlinux/julia-aur/os/x86_64" 
CHROOT="$HOME/chroot" 
REPO_PATH="$SRV_DIR/julia-aur.db.tar.gz" # path to pacman database

# dependencies's parent folder in $PACKAGE_DIR should have a NN_filename numeric prefix (i.e 00_spotify)
# in case there are dependencies in julia-aur

CHROOT_GENERATED=0

# $1 == package name 
generate_package() {
	if [[ $CHROOT_GENERATED == 0 ]]; then
		sudo rm -rf $CHROOT
		mkdir $CHROOT
		mkarchroot -C /etc/pacman.conf -M /etc/makepkg.conf $CHROOT/root base-devel
		CHROOT_GENERATED=1
	fi

	# check for dependencies being built and stored in julia-aur
	arch-nspawn $CHROOT/root pacman -Syu
	
	cd $PACKAGE_DIR/$1
	makepkg --verifysource -f
	makechrootpkg -c -r $CHROOT

	PACKAGES=$(makepkg --packagelist | grep -v "\-debug")

	for package in $PACKAGES; do
		repo-add $REPO_PATH $package	
	done
}

update_package() {
	cd $PACKAGE_DIR/$1
	
	# clean aur folder and check for updates
	git clean -f
	git remote update

	PACKAGES=$(makepkg --packagelist | grep -v "\-debug")	
	BEHIND=$(git status -uno | grep -o behind)
	
	if [[ "$``BEHIND" == "behind" ]]; then
		echo "$1 is behind"
			
		# remove out of date packages
		for file in $PACKAGES; do
			if test -f $file; then
				echo -e "\t removing $file"
				rm $file
			fi
		done

		git pull
		generate_package $1
	else
		echo "$1 is up to date"
		
		# check for unbuilt packages
		for file in $PACKAGES; do 
			if ! test -f $file; then
				echo -e "\t$file does not exist"
				generate_package $1
				break
			fi
		done
	fi
}

update_all() {
	for repo in $(ls $PACKAGE_DIR); do
		update_package $repo
	done

	timedatectl show -P TimeUSec > /srv/http/repo_last_updated

	cd $PACKAGE_DIR
	sudo pacman -Syu
}

main() {
	# machine needs to be up to date
	sudo pacman -Syu

	if [ -z ${1+x} ]; then
		update_all
	else
		if [[ "$1" != "--check" ]]; then
			update_package $1
		fi
	fi

	# required to check julia-aur 
	sudo pacman -Syu

	echo "left hand side == output of pacman -Sl julia-aur"
	echo "right hand side == packages in $SRV_DIR"

	diff -y <(pacman -Sl julia-aur | cut -d" " -f 2,3 | sort) <(ls $SRV_DIR | grep -v "julia" | rev | cut -d"." -f 1,2,3 --complement | cut -d"-" -f 1 --complement | sed 's/-/ /2' | rev | sort)

	echo "left hand side == output of pacman -Sl julia-aur"
	echo "right hand side == folders in $PACKAGE_DIR"

	diff -y <(pacman -Sl julia-aur | cut -d" " -f 2 | sort) <(ls $PACKAGE_DIR | sed 's/[0-9]\+_//g' | sort)
}

main $1