//
// Copyright (c) 2008 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "GPBookmarkSync.h"

#import <GData/GData.h>

#import "GPKeychainItem.h"
#import "SharedConstants.h"

@interface GPBookmarkSync (Private)

- (void)requestBookmarksStartingFrom:(NSUInteger)start;
- (NSArray*)bookmarksFromData:(NSData*)data;
- (void)fetch:(GTMHTTPFetcher*)fetcher
    finishedWithData:(NSData*)data
    error:(NSError*)error;

@end

@implementation GPBookmarkSync

- (id)initWithManager:(id<GPSyncManager>)manager {
  if ((self = [super init])) {
    manager_ = manager;
    bookmarks_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  [bookmarks_ release];
  [super dealloc];
}

- (void)fetchAllItemsBasicInfo {
  [bookmarks_ removeAllObjects];
  [self requestBookmarksStartingFrom:0];
}

- (void)fetchFullInfoForItems:(NSArray*)items {
  // All the data is already present, so nothing to do.
  [manager_ fullItemsInfo:items fetchedForSource:self];
  [manager_ fullItemsInfoFetchCompletedForSource:self];
}

- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item {
  return @"gbookmark";
}

- (NSArray*)itemExtensions {
  return [NSArray arrayWithObject:@"gbookmark"];
}

- (NSString*)displayName {
  return @"Google Bookmarks";
}

#pragma mark -

- (void)requestBookmarksStartingFrom:(NSUInteger)start {
  NSString* requestURI = [NSString stringWithFormat:
      @"https://www.google.com/bookmarks/lookup?output=rss&start=%lu", start];
  NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:requestURI]];
  GTMHTTPFetcher* fetcher = [GTMHTTPFetcher fetcherWithRequest:request];
  GPKeychainItem* loginCredentials = [manager_ accountCredentials];
  if (loginCredentials) {
    [fetcher setCredential:[NSURLCredential credentialWithUser:[loginCredentials username]
                                                      password:[loginCredentials password]
                                                   persistence:NSURLCredentialPersistenceForSession]];
  }
  [fetcher setRetryEnabled:YES];
  [fetcher setMaxRetryInterval:60.0];
  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(fetch:finishedWithData:error:)];
}

- (NSArray*)bookmarksFromData:(NSData*)data {
  NSXMLDocument* bookmarksXML = [[[NSXMLDocument alloc] initWithData:data
                                                             options:0
                                                               error:nil] autorelease];
  NSArray* bookmarkNodes = [bookmarksXML nodesForXPath:@"//item" error:NULL];
  NSMutableArray* bookmarkItems = [NSMutableArray array];
  for (NSXMLNode* bookmark in bookmarkNodes) {
    NSMutableDictionary* bookmarkInfo = [NSMutableDictionary dictionary];
    NSMutableArray* keywords = [NSMutableArray array];
    for (NSXMLNode* infoNode in [bookmark children]) {
      if ([[infoNode name] isEqualToString:@"title"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:(NSString*)kMDItemTitle];
      } else if ([[infoNode name] isEqualToString:@"link"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:(NSString*)kGPMDItemURL];
      } else if ([[infoNode name] isEqualToString:@"pubDate"]) {
        [bookmarkInfo setObject:[NSDate dateWithNaturalLanguageString:[infoNode stringValue]]
                         forKey:kGPMDItemModificationDate];
      } else if ([[infoNode name] isEqualToString:@"smh:bkmk_id"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:kGPMDItemUID];
      } else if ([[infoNode name] isEqualToString:@"smh:bkmk_label"]) {
        [keywords addObject:[infoNode stringValue]];
      } else if ([[infoNode name] isEqualToString:@"smh:bkmk_annotation"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:(NSString*)kMDItemDescription];
      }
    }
    if ([keywords count] > 0)
      [bookmarkInfo setObject:keywords forKey:(NSString*)kMDItemKeywords];
    [bookmarkItems addObject:bookmarkInfo];
  }
  return bookmarkItems;
}

#pragma mark -

- (void)fetch:(GTMHTTPFetcher*)fetcher
    finishedWithData:(NSData*)data
    error:(NSError*)error {
  if (error) {
    [manager_ infoFetchFailedForSource:self withError:error];
    [bookmarks_ removeAllObjects];
  } else {
    NSArray* newBookmarks = [self bookmarksFromData:data];
    // The bookmarks feed returns chunks, not everything, so unless there were
    // no bookmarks in the response we assume there are more. Once we hit an
    // empty feed, we can be sure we've walked the entire list.
    if ([newBookmarks count] > 0) {
      [bookmarks_ addObjectsFromArray:newBookmarks];
      [self requestBookmarksStartingFrom:[bookmarks_ count]];
    } else {
      [manager_ basicItemsInfo:bookmarks_ fetchedForSource:self];
      [bookmarks_ removeAllObjects];
    }
  }
}

@end
