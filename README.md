tsg-mailcow is intended to be a simple and compatible successor of [mailcow-mailman3-dockerized](https://github.com/Shadowghost/mailcow-mailman3-dockerized).
 
Reasons for this are: 
- mailcow-mailman3-dockerized is abandoned
- mailcow-mailman3-dockerized is based on mailcow, but can't be updated like mailcow
 
So tsg-mailcow utilizes the following approach to overcome this:
- the master branch is mailcow upstream
- the mailman3 branch starts at mailcow commit 477e4dab13cf164340aaea05a6a2e79744a43b04. The first commit is intended to match the mailcow-mailman3-dockerized branch at commit 7c9e89dce588568c5b528b3b9d0e01f42e485952 as close as possible, without introducing obvious bugs included there. See also at [Commit 7c9e89dce588568c5b528b3b9d0e01f42e485952 of mailcow-mailman3-dockerized](https://github.com/Shadowghost/mailcow-mailman3-dockerized/tree/7c9e89dce588568c5b528b3b9d0e01f42e485952)
- the mailman3 branch shall take all changes needed for running mailman.


# Dependencies
yq: install with ```sudo snap install yq```


# Links

[mailcow-dockerized](https://github.com/mailcow/mailcow-dockerized)
[mailcow-mailman3-dockerized](https://github.com/Shadowghost/mailcow-mailman3-dockerized)

