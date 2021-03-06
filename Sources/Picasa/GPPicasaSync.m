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

#import "GPPicasaSync.h"

#import <GData/GData.h>

#import "GDataSourceUtils.h"
#import "GPKeychainItem.h"
#import "SharedConstants.h"
#import "PWAInfoKeys.h"

#define kPWADictionaryTypeKey @"_PWAType"

@interface GPPicasaSync (Private)
- (void)fetchItemsWithKind:(NSString*)kind didFinishSelector:(SEL)doneSelector;
- (void)addBasicInfoFromFeed:(GDataFeedBase *)feed;
- (NSMutableDictionary*)baseDictionaryForPhotoBase:(GDataEntryPhotoBase*)entry;
- (NSDictionary*)dictionaryForPhoto:(GDataEntryPhoto*)photo;
- (NSDictionary*)dictionaryForAlbum:(GDataEntryPhotoAlbum*)album;
- (NSString*)thumbnailURLForEntry:(GDataEntryPhotoBase*)entry;
- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithAlbums:(GDataFeedBase *)albumList
                error:(NSError*)error;
- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithPhotos:(GDataFeedBase *)photoList
                error:(NSError*)error;
@end

@implementation GPPicasaSync

- (id)initWithManager:(id<GPSyncManager>)manager {
  if ((self = [super init])) {
    manager_ = manager;
  }
  return self;
}

- (void)dealloc {
  [photosService_ release];
  [username_ release];
  [basicInfo_ release];
  [super dealloc];
}

- (void)fetchAllItemsBasicInfo {
  GPKeychainItem* loginCredentials = [manager_ accountCredentials];
  if (!loginCredentials) {
    NSError* error = [NSError gp_loginErrorWithDescriptionKey:@"LoginFailed"];
    [manager_ infoFetchFailedForSource:self withError:error];
    return;
  }

  [photosService_ autorelease];
  photosService_ = [[GDataServiceGooglePhotos alloc] init];
  [photosService_ gp_configureWithCredentials:loginCredentials];
  [username_ autorelease];
  username_ = [[loginCredentials username] copy];
  [basicInfo_ autorelease];
  basicInfo_ = [[NSMutableArray alloc] init];

  [self fetchItemsWithKind:kGDataGooglePhotosKindAlbum
         didFinishSelector:@selector(serviceTicket:finishedWithAlbums:error:)];
}

- (void)fetchFullInfoForItems:(NSArray*)items {
  [manager_ fullItemsInfo:items fetchedForSource:self];
  [manager_ fullItemsInfoFetchCompletedForSource:self];
}

- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item {
  if ([[item objectForKey:kPWADictionaryTypeKey] isEqual:kPWATypeAlbum])
    return @"pwaalbum";
  return @"pwaphoto";
}

- (NSArray*)itemExtensions {
  return [NSArray arrayWithObjects:@"pwaalbum", @"pwaphoto", nil];
}

- (NSString*)displayName {
  return @"Picasa Web Albums";
}

#pragma mark -

- (void)fetchItemsWithKind:(NSString*)kind didFinishSelector:(SEL)doneSelector {
  NSString* feedURI =
    [[GDataServiceGooglePhotos photoFeedURLForUserID:username_
                                             albumID:nil
                                           albumName:nil
                                             photoID:nil
                                                kind:kind
                                              access:nil] absoluteString];
  // Ideally we would use https, but the feed redirects when accessed that way.
  //if ([feedURI hasPrefix:@"http:"])
  //  feedURI = [@"https:" stringByAppendingString:[feedURI substringFromIndex:5]];
  [photosService_ fetchFeedWithURL:[NSURL URLWithString:feedURI]
                          delegate:self
                 didFinishSelector:doneSelector];
}

- (void)addBasicInfoFromFeed:(GDataFeedBase *)feed {
  for (GDataEntryBase* entry in [feed entries]) {
    @try {
      NSDictionary* entryInfo = nil;
      if ([entry isKindOfClass:[GDataEntryPhoto class]]) {
        entryInfo = [self dictionaryForPhoto:(GDataEntryPhoto*)entry];
      } else if ([entry isKindOfClass:[GDataEntryPhotoAlbum class]]) {
        entryInfo = [self dictionaryForAlbum:(GDataEntryPhotoAlbum*)entry];
      } else {
        NSLog(@"Unexpected entry in PWA feed: %@", entry);
        continue;
      }

      if (entryInfo)
        [basicInfo_ addObject:entryInfo];
      else
        NSLog(@"Couldn't get info for PWA entry: %@", entry);
    } @catch (id exception) {
      NSLog(@"Caught exception while processing basic item info: %@", exception);
    }
  }
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithAlbums:(GDataFeedBase *)albumList
                error:(NSError*)error {
  if (error) {
    [manager_ infoFetchFailedForSource:self
                             withError:[error gp_reportableError]];
    return;
  }

  [self addBasicInfoFromFeed:albumList];

  [self fetchItemsWithKind:kGDataGooglePhotosKindPhoto
         didFinishSelector:@selector(serviceTicket:finishedWithPhotos:error:)];
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithPhotos:(GDataFeedBase *)photoList
                error:(NSError*)error {
  if (error) {
    [manager_ infoFetchFailedForSource:self
                             withError:[error gp_reportableError]];
    return;
  }

  [self addBasicInfoFromFeed:photoList];

  [manager_ basicItemsInfo:basicInfo_ fetchedForSource:self];
  [basicInfo_ autorelease];
  basicInfo_ = nil;
}

- (NSDictionary*)dictionaryForPhoto:(GDataEntryPhoto*)photo {
  NSMutableDictionary* infoDictionary = [self baseDictionaryForPhotoBase:photo];
  [infoDictionary setObject:kPWATypePhoto forKey:kPWADictionaryTypeKey];
  NSDate* creationDate = [[photo timestamp] dateValue];
  if (creationDate) {
    [infoDictionary setObject:creationDate
                       forKey:(NSString*)kMDItemContentCreationDate];
  }
  [infoDictionary setObject:[photo width] forKey:(NSString*)kMDItemPixelWidth];
  [infoDictionary setObject:[photo height] forKey:(NSString*)kMDItemPixelHeight];
  NSArray* keywords = [[[photo mediaGroup] mediaKeywords] keywords];
  if ([keywords count] > 0)
    [infoDictionary setObject:keywords forKey:(NSString*)kMDItemKeywords];
  for (GDataEXIFTag* tag in [[photo EXIFTags] tags]) {
    NSString* tagName = [tag name];
    if ([tagName isEqualToString:@"exposure"])
      [infoDictionary setObject:[tag doubleNumberValue]
                         forKey:(NSString*)kMDItemExposureTimeSeconds];
    if ([tagName isEqualToString:@"flash"])
      [infoDictionary setObject:[tag boolNumberValue]
                         forKey:(NSString*)kMDItemFlashOnOff];
    if ([tagName isEqualToString:@"focallength"])
      [infoDictionary setObject:[tag doubleNumberValue]
                         forKey:(NSString*)kMDItemFocalLength];
    if ([tagName isEqualToString:@"iso"])
      [infoDictionary setObject:[tag intNumberValue]
                         forKey:(NSString*)kMDItemISOSpeed];
    if ([tagName isEqualToString:@"make"])
      [infoDictionary setObject:[tag stringValue]
                         forKey:(NSString*)kMDItemAcquisitionMake];
    if ([tagName isEqualToString:@"model"])
      [infoDictionary setObject:[tag stringValue]
                         forKey:(NSString*)kMDItemAcquisitionModel];
  }
  // TODO: Ideally we would set kMDItemAlbum, but keeping all the photos correct
  // when an album is renamed will take some juggling.
  return infoDictionary;
}

- (NSDictionary*)dictionaryForAlbum:(GDataEntryPhotoAlbum*)album {
  NSMutableDictionary* infoDictionary = [self baseDictionaryForPhotoBase:album];
  [infoDictionary setObject:kPWATypeAlbum forKey:kPWADictionaryTypeKey];
  [infoDictionary setObject:[[album timestamp] dateValue] forKey:(NSString*)kMDItemContentCreationDate];
  [infoDictionary setObject:[album location] forKey:kAlbumDictionaryLocationKey];
  return infoDictionary;
}

// common dictionary items for photos and albums.
- (NSMutableDictionary*)baseDictionaryForPhotoBase:(GDataEntryPhotoBase*)entry {
  return [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                      [entry GPhotoID], kGPMDItemUID,
                           [[entry title] stringValue], (NSString*)kMDItemTitle,
                            [[entry updatedDate] date], kGPMDItemModificationDate,
      [[entry authors] gp_peopleStringsForGDataPeople], (NSString*)kMDItemAuthors,
                               [[entry HTMLLink] href], (NSString*)kGPMDItemURL,
                [[entry photoDescription] stringValue], (NSString*)kMDItemDescription,
                     [self thumbnailURLForEntry:entry], kPWADictionaryThumbnailURLKey,
                                                        nil];
}

- (NSString*)thumbnailURLForEntry:(GDataEntryPhotoBase*)entry {
  if (![entry respondsToSelector:@selector(mediaGroup)])
    return @"";
  NSArray *thumbnails = [[(id)entry mediaGroup] mediaThumbnails];
  if ([thumbnails count] > 0)
    return [[thumbnails objectAtIndex:0] URLString];
  return @"";
}

@end
