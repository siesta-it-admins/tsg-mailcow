# Updating tsg-mailcow

Updating tsg-mailcow is a two step process. First you have to catch up with upstream mailcow, then you have to make ready for deployment.


## Developers workstation

This instructions assume you are running your dev box with Linux. 

### Github.com setup

If you use several SSH-Keys for github.com, you can setup a distinct entry in your .ssh/config:
```
Host github_as_siesta-user
	HostName github.com
	User git
	IdentityFile ~/.ssh/<your_key>
	IdentitiesOnly yes	
```
Replace github.com in the following commands with github_as_siesta-user


### Initial setup of working copy (do this once)

Clone repository:

```
git clone git@github.com:siesta-it-admins/tsg-mailcow.git
cd tsg-mailcow
```

Add a remote for upstream
```
git remote add upstream https://github.com/mailcow/mailcow-dockerized.git
```

### Update working copy (whenever you want to create a new version for deployment)
```
git fetch upstream
git push --set-upstream origin --tags
git checkout mailman3
git merge upstream/master
```
Potentially merge conflicts arise at this point. Solve them wise and commit them.
Then push them.
```
git push
```

## Deployment on production

On the productuion machine, you need to fetch the changes from tsg-mailcow.git, then integrate into the running copy.

### Backup

### Update
```
cd /opt/tsg-mailcow
systemctl stop docker-compose-mailcow
git pull
git merge origin/mailman3
docker-compose pull
systemctl start docker-compose-mailcow


