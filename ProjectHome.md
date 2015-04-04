
---


---


---


**Note: This project is not currently maintained, and the last builds no longer function correctly with the current versions of the Google services listed below.** Bookmarks no longer sync, for example, nor does the full text of Docs. Significant rewriting would be necessary to restore functionality. There are no current plans for a rewrite, but the project is open source, and patches are welcome.


---


---


---


![http://precipitate.googlecode.com/files/Precipitate.png](http://precipitate.googlecode.com/files/Precipitate.png)

Precipitate lets you search for and launch the information you have stored in the cloud from within Spotlight or [Quick Search Box](http://code.google.com/p/qsb-mac/). It currently supports the following services:
  * Google Docs (including Google Apps accounts)
  * Google Bookmarks
  * Picasa Web Albums

![http://precipitate.googlecode.com/files/screenshot.png](http://precipitate.googlecode.com/files/screenshot.png)

Precipitate works by creating files on your machine that are imported by Spotlight, then periodically checking in with the server and updating the local files to reflect any changes. Note that changes may take up to an hour to be visible in local searches.

## Installation and Setup ##

Open the Precipitate preference pane, and install it either for yourself or for all users. Enter your Google account information into the preference pane, check the box for each service you want to make searchable, then press "Refresh Now" to start the initial import (note that this may take some time, depending on how much data you have). Then just start searching!

Current versions of Precipitate require OS X 10.5 or later. 10.4 users should [download 1.0.5](http://code.google.com/p/precipitate/downloads/list)