/**
 * Copyright (C) 2009 bdferris <bdferris@onebusaway.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *         http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "OBAModelFactory.h"
#import "OBALogger.h"
#import "OBACommon.h"

#import "OBAAgency.h"
#import "OBARoute.h"
#import "OBAStop.h"
#import "OBAStopPreferences.h"
#import "OBAArrivalAndDeparture.h"
#import "OBAArrivalsAndDeparturesForStop.h"
#import "OBAPlacemark.h"
#import "OBAAgencyWithCoverage.h"

#import "OBAJsonDigester.h"
#import "OBASetCoordinatePropertyJsonDigesterRule.h"
#import "OBACreateManagedEntityJsonDigesterRule.h"

static NSString * const kOBAAgency = @"OBAAgency";
static NSString * const kOBARoute = @"OBARoute";
static NSString * const kOBAStop = @"OBAStop";
static NSString * const kOBAStopPreferences = @"OBAStopPreferences";


@interface OBAModelFactory (Private)

- (NSDictionary*) getDigesterParameters;

- (OBAAgency*) getAgencyFromDictionary:(NSDictionary*)dictionary error:(NSError**)error;
- (OBARoute*) getRouteFromDictionary:(NSDictionary*)dictionary error:(NSError**)error;
- (OBAStop*) getStopFromDictionary:(NSDictionary*)dictionary error:(NSError**)error;
- (OBAArrivalAndDeparture*) getArrivalAndDepartureFromDictionary:(NSDictionary*)dictionary error:(NSError**)error;

- (OBARoute*) getRouteWithId:(NSString*)routeId error:(NSError**)error;
- (OBAStop*) getStopWithId:(NSString*)stopId error:(NSError**)error;

- (void) saveIfNeeded:(NSError**)error;

- (id) getEntity:(NSString*)entityName entityIdProperty:(NSString*)entityIdProperty entityId:(NSString*)entityId error:(NSError**)error;

- (void) setManagedObjectIdForEntity:(NSString*)entityName withEntityId:(NSString*)entityId managedObjectId:(NSManagedObjectID*)managedObjectId;
- (NSManagedObjectID*) getManagedObjectIdForEntity:(NSString*)entityName withEntityId:(NSString*)entityId;

- (BOOL) setValueForKey:(NSString*)objKey fromDictionary:(NSDictionary*)dictionary withDictionaryKey:(NSString*)dictKey onObject:(NSObject*)object required:(BOOL)required error:(NSError**)error;
- (BOOL) setDoubleValueForKey:(NSString*)objKey fromDictionary:(NSDictionary*)dictionary withDictionaryKey:(NSString*)dictKey onObject:(NSObject*)object required:(BOOL)required error:(NSError**)error;

@end

@interface OBAJsonDigester (CustomDigesterRules)

- (void) addAgencyRulesWithPrefix:(NSString*)prefix;
- (void) addSetCoordinatePropertyRule:(NSString*)propertyName withPrefix:(NSString*)prefix method:(OBASetCoordinatePropertyMethod)method;

@end


@implementation OBAModelFactory

- (id) initWithManagedObjectContext:(NSManagedObjectContext*)managedObjectContext {
	if( self = [super init] ) {
		_context = [managedObjectContext retain];
		_entityIdMappings = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void) dealloc {
	[_context release];
	[_entityIdMappings release];
	[super dealloc];
}
	
- (NSArray*) getStopsFromJSONArray:(NSArray*)jsonArray error:(NSError**)error {
	
	NSMutableArray * stops = [NSMutableArray arrayWithCapacity:[jsonArray count]];
	
	for( NSDictionary * dictionary in jsonArray ) {
		OBAStop * stop = [self getStopFromDictionary:dictionary error:error];
		if( *error )
			return nil;
		[stops addObject:stop];
	}
	
	[self saveIfNeeded:error];

	if( *error )
		return nil;
	
	return stops;
}

- (NSArray*) getRoutesFromJSONArray:(NSArray*)jsonArray error:(NSError**)error {

	NSMutableArray * routes = [NSMutableArray arrayWithCapacity:[jsonArray count]];
	
	for( NSDictionary * dictionary in jsonArray ) {
		OBARoute * route = [self getRouteFromDictionary:dictionary error:error];
		if( *error )
			return nil;
		[routes addObject:route];
	}
	
	[self saveIfNeeded:error];
	
	if( *error )
		return nil;
	
	return routes;
}

- (NSArray*) getPlacemarksFromJSONObject:(id)jsonObject error:(NSError**)error {
	
	NSMutableArray * placemarks = [NSMutableArray array];
	
	OBAJsonDigester * digester = [[OBAJsonDigester alloc] init];
	[digester addObjectCreateRule:[OBAPlacemark class] forPrefix:@"/Placemark/[]"];
	[digester addSetPropertyRule:@"address" forPrefix:@"/Placemark/[]/address"];
	[digester addSetNext:@selector(addObject:) forPrefix:@"/Placemark/[]"];
	
	OBASetCoordinatePropertyJsonDigesterRule * rule = [[OBASetCoordinatePropertyJsonDigesterRule alloc] initWithPropertyName:@"coordinate"];
	[digester addRule:rule forPrefix:@"/Placemark/[]/Point/coordinates"];
	[rule release];
	
	[digester parse:jsonObject withRoot:placemarks];
	[digester release];
	
	return placemarks;
}

- (NSArray*) getAgenciesWithCoverageFromJson:(id)jsonArray error:(NSError**)error {

	NSMutableArray * results = [NSMutableArray array];
	
	OBAJsonDigester * digester = [[OBAJsonDigester alloc] init];
	[digester addObjectCreateRule:[OBAAgencyWithCoverage class] forPrefix:@"/[]"];
	[digester addAgencyRulesWithPrefix:@"/[]/agency"];
	[digester addSetNext:@selector(setAgency:) forPrefix:@"/[]/agency"];
	[digester addSetCoordinatePropertyRule:@"coordinate" withPrefix:@"/[]" method:OBASetCoordinatePropertyMethodLatLon];
	[digester addSetNext:@selector(addObject:) forPrefix:@"/[]"];
	
	[digester parse:jsonArray withRoot:results parameters:[self getDigesterParameters]];
	[digester release];
	
	return results;
}

- (OBAArrivalsAndDeparturesForStop*) getArrivalsAndDeparturesForStopFromJSON:(NSDictionary*)jsonDictionary error:(NSError**)error {
	
	OBAArrivalsAndDeparturesForStop * ads = [[[OBAArrivalsAndDeparturesForStop alloc] init] autorelease];
	
	NSDictionary * stopDict = [jsonDictionary valueForKey:@"stop"];
	ads.stop = [self getStopFromDictionary:stopDict error:error];
	if( *error )
		return nil;
	
	NSArray * arrivalObjects = [jsonDictionary valueForKey:@"arrivalsAndDepartures"];	
	NSMutableArray * localArrivalsAndDepartures = [NSMutableArray arrayWithCapacity:[arrivalObjects count]];
	
	for(int i=0; i<[arrivalObjects count]; i++) {
		NSDictionary * arrivalObject = [arrivalObjects objectAtIndex:i];
		OBAArrivalAndDeparture * ad = [self getArrivalAndDepartureFromDictionary:arrivalObject error:error];
		if( *error )
			return nil;
		
		[localArrivalsAndDepartures addObject:ad];
	}
	
	ads.arrivalsAndDepartures = localArrivalsAndDepartures;
	
	[self saveIfNeeded:error];
	
	if( *error )
		return nil;
	
	return ads;
}

@end

@implementation OBAModelFactory (Private)

- (NSDictionary*) getDigesterParameters {
	NSMutableDictionary * params = [NSMutableDictionary dictionary];
	[params setObject:_entityIdMappings forKey:@"entityIdMappings"];
	[params setObject:_context forKey:@"managedObjectContext"];
	return params;
}

- (OBAAgency*) getAgencyFromDictionary:(NSDictionary*)dictionary error:(NSError**)error {
	NSString * agencyId = [dictionary objectForKey:@"id"];
	
	if( agencyId == nil ) {
		OBALogSevere(@"No id attribute found for agency");
		return nil;
	}
	
	OBAAgency * agency = [self getEntity:kOBAAgency entityIdProperty:@"agencyId" entityId:agencyId error:error];
	
	if(*error)
		return nil;
	
	if( ! [self setValueForKey:@"name" fromDictionary:dictionary withDictionaryKey:@"name" onObject:agency required:TRUE error:error] )
		return nil;
	if( ! [self setValueForKey:@"url" fromDictionary:dictionary withDictionaryKey:@"url" onObject:agency required:TRUE error:error] )
		return nil;
	
	return agency;
}

- (OBARoute*) getRouteFromDictionary:(NSDictionary*)dictionary error:(NSError**)error {
	NSString * routeId = [dictionary objectForKey:@"id"];
	
	if( routeId == nil) {
		OBALogSevere(@"No id attribute found for route");
		return nil;
	}
	
	OBARoute * route = [self getEntity:kOBARoute entityIdProperty:@"routeId" entityId:routeId error:error];
	
	if(*error)
		return nil;
	
	if( ! [self setValueForKey:@"shortName" fromDictionary:dictionary withDictionaryKey:@"shortName" onObject:route required:TRUE error:error] )
		return nil;
	if( ! [self setValueForKey:@"longName" fromDictionary:dictionary withDictionaryKey:@"longName" onObject:route required:TRUE error:error] )
		return nil;
	
	NSDictionary * agencyDictionary = [dictionary objectForKey:@"agency"];
	OBAAgency * agency = [self getAgencyFromDictionary:agencyDictionary error:error];
	if( ! [agency isEqual:route.agency] ) {
		route.agency = agency;
	}
	
	if( *error )
		return nil;
	
	return route;
}

- (OBAStop*) getStopFromDictionary:(NSDictionary*)dictionary error:(NSError**)error {
	
	NSString * stopId = [dictionary objectForKey:@"id"];
	
	if( stopId == nil) {
		OBALogSevere(@"No id attribute found for stop");
		return nil;
	}
	
	OBAStop * stop = [self getEntity:kOBAStop entityIdProperty:@"stopId" entityId:stopId error:error];
	if( *error )
		return nil;
	
	if( ! [self setValueForKey:@"name" fromDictionary:dictionary withDictionaryKey:@"name" onObject:stop required:TRUE error:error] )
		return nil;
	if( ! [self setValueForKey:@"code" fromDictionary:dictionary withDictionaryKey:@"code" onObject:stop required:FALSE error:error] )
		return nil;
	if( ! [self setValueForKey:@"direction" fromDictionary:dictionary withDictionaryKey:@"direction" onObject:stop required:FALSE error:error] )
		return nil;
	
	if( ! [self setDoubleValueForKey:@"latitude" fromDictionary:dictionary withDictionaryKey:@"lat" onObject:stop required:TRUE error:error] )
		return nil;
	if( ! [self setDoubleValueForKey:@"longitude" fromDictionary:dictionary withDictionaryKey:@"lon" onObject:stop required:TRUE error:error] )
		return nil;
	
	NSArray * routeElements = [dictionary objectForKey:@"routes"];
	
	
	if( [stop.routes count] != [routeElements count])
		stop.routes = [NSSet set];
	
	for( NSDictionary * routeDictionary in routeElements ) {
		OBARoute * route = [self getRouteFromDictionary:routeDictionary error:error];
		if( *error ) 
			return nil;
		if( ! [stop.routes containsObject:route] ) {
			[stop addRoutesObject:route];
		}
	}
	
	if( stop.preferences == nil ) {
		OBAStopPreferences * prefs = [NSEntityDescription insertNewObjectForEntityForName:kOBAStopPreferences inManagedObjectContext:_context];
		stop.preferences = prefs;
	}
	
	return stop;
}

- (OBAArrivalAndDeparture*) getArrivalAndDepartureFromDictionary:(NSDictionary*)dictionary error:(NSError**)error {

	OBAArrivalAndDeparture * ad = [[[OBAArrivalAndDeparture alloc] init] autorelease];
	
	NSString * routeId = [dictionary objectForKey:@"routeId"];
	ad.route = [self getRouteWithId:routeId error:error];
	if( *error )
		return nil;
	
	ad.routeShortName = [dictionary objectForKey:@"routeShortName"];
	ad.tripId = [dictionary objectForKey:@"tripId"];
	ad.tripHeadsign = [dictionary objectForKey:@"tripHeadsign"];

	/*
	NSString * stopId = [dictionary objectForKey:@"stopId"];
	ad.stop = [self getStopWithId:stopId error:error];
	if( *error )
		return nil;
	 */
	
	ad.scheduledArrivalTime = [[dictionary valueForKey:@"scheduledArrivalTime"] longLongValue];
	ad.predictedArrivalTime = [[dictionary valueForKey:@"predictedArrivalTime"] longLongValue];
	
	ad.scheduledDepartureTime = [[dictionary valueForKey:@"scheduledDepartureTime"] longLongValue];
	ad.predictedDepartureTime = [[dictionary valueForKey:@"predictedDepartureTime"] longLongValue];
	
	return ad;
}

- (OBARoute*) getRouteWithId:(NSString*)routeId error:(NSError**)error {
	return [self getEntity:kOBARoute entityIdProperty:@"routeId" entityId:routeId error:error];
}

- (OBAStop*) getStopWithId:(NSString*)stopId error:(NSError**)error {
	return [self getEntity:kOBAStop entityIdProperty:@"stopId" entityId:stopId error:error];
}

- (void) saveIfNeeded:(NSError**)error {
	if( [_context hasChanges] )
		[_context save:error];
}

- (id) getEntity:(NSString*)entityName entityIdProperty:(NSString*)entityIdProperty entityId:(NSString*)entityId error:(NSError**)error {
	
	NSManagedObjectID * managedObjectId = [self getManagedObjectIdForEntity:entityName withEntityId:entityId];
	
	if( managedObjectId != nil ) {
		NSError * error = nil;
		NSManagedObject * obj = [_context existingObjectWithID:managedObjectId error:&error];
		if( error ) {
			NSString * uri = [[managedObjectId URIRepresentation] absoluteString];
			OBALogSevereWithError(error,@"Error retrievingExistingObjectWithID: entityName=%@ entityId=%@ managedId=%@",entityName,entityId,uri);
		}
		else {
			if( [entityId isEqual:[obj valueForKey:entityIdProperty]] )
				return obj;
			NSString * uri = [[managedObjectId URIRepresentation] absoluteString];
			OBALogWarning(@"Entity id mismatch: entityName=%@ entityId=%@ managedId=%@",entityName,entityId,uri);
		}
	}
	
	NSEntityDescription *entityDescription = [NSEntityDescription
											  entityForName:entityName inManagedObjectContext:_context];
	
	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	[request setEntity:entityDescription];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K == %@", entityIdProperty, entityId];
	[request setPredicate:predicate];
	
	NSArray *fetchedObjects = [_context executeFetchRequest:request error:error];
	
	if (fetchedObjects == nil) {
		OBALogSevereWithError((*error),@"Error fetching entity: name=%@ idProperty=%@ id=%@",entityName,entityIdProperty,entityId);
		return nil;
	}
	
	if( [fetchedObjects count] == 0) {
		id entity = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:_context];
		[entity setValue:entityId forKey:entityIdProperty];
		return entity;
	}
	
	if( [fetchedObjects count] > 1 ) {
		OBALogSevere(@"Duplicate entities: entityName=%@ entityIdProperty=%@ entityId=%@ count=%d",entityName,entityIdProperty,entityId,[fetchedObjects count]);
		(*error) = [NSError errorWithDomain:OBAErrorDomain code:kOBAErrorDuplicateEntity userInfo:nil];
		return nil;
	}
	
	NSManagedObject * entity = [fetchedObjects objectAtIndex:0];
	[self setManagedObjectIdForEntity:entityName withEntityId:entityId managedObjectId:[entity objectID]];
	return entity;
}

- (void) setManagedObjectIdForEntity:(NSString*)entityName withEntityId:(NSString*)entityId managedObjectId:(NSManagedObjectID*)managedObjectId {
	NSMutableDictionary * entityIdMapping = [_entityIdMappings objectForKey:entityName];
	if( entityIdMapping == nil ) {
		entityIdMapping = [NSMutableDictionary dictionary];
		[_entityIdMappings setObject:entityIdMapping forKey:entityName];
	}
	[entityIdMapping setObject:managedObjectId forKey:entityId];
}

- (NSManagedObjectID*) getManagedObjectIdForEntity:(NSString*)entityName withEntityId:(NSString*)entityId {
	NSDictionary * entityIdMapping = [_entityIdMappings objectForKey:entityName];
	if( entityIdMapping == nil )
		return nil;
	return [entityIdMapping objectForKey:entityId];
}


#pragma mark -
#pragma mark Methods for transfering data from collections to objects

- (BOOL) setValueForKey:(NSString*)objKey fromDictionary:(NSDictionary*)dictionary withDictionaryKey:(NSString*)dictKey onObject:(NSObject*)object required:(BOOL)required error:(NSError**)error {
	
	id value = [dictionary valueForKey:dictKey];
	if( value == nil) {
		if( required ) {
			*error = [NSError errorWithDomain:OBAErrorDomain code:kOBAErrorMissingFieldInData userInfo:nil];
			return FALSE;
		}
	}
	
	id existingValue = [object valueForKey:objKey];
	
	if( value == nil && existingValue == nil )
		return TRUE;
	if( value != nil && [value isEqual:existingValue] )
		return TRUE;
	
	[object setValue:value forKey:objKey];
	
	return TRUE;
}

- (BOOL) setDoubleValueForKey:(NSString*)objKey fromDictionary:(NSDictionary*)dictionary withDictionaryKey:(NSString*)dictKey onObject:(NSObject*)object required:(BOOL)required error:(NSError**)error {
	NSNumber * value = [dictionary valueForKey:dictKey];
	if( value == nil) {
		if( required ) {
			*error = [NSError errorWithDomain:OBAErrorDomain code:kOBAErrorMissingFieldInData userInfo:nil];
			return FALSE;
		}
	}
	
	NSNumber * existingValue = [object valueForKey:objKey];
	
	if( value == nil && existingValue == nil )
		return TRUE;
	if( value != nil && existingValue != nil || [value doubleValue] == [existingValue doubleValue])
		return TRUE;
	
	[object setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:objKey];
	
	return TRUE;
}

@end
	
@implementation OBAJsonDigester (CustomDigesterRules)
	
- (void) addAgencyRulesWithPrefix:(NSString*)prefix {

	OBACreateManagedEntityJsonDigesterRule * rule = [[OBACreateManagedEntityJsonDigesterRule alloc] initWithEntityName:kOBAAgency entityIdProperty:@"agencyId" jsonIdProperty:@"id"];
	[self addRule:rule forPrefix:prefix];
	[rule release];
	
	[self addSetPropertyRule:@"name" forPrefix:[self extendPrefix:prefix withValue:@"name"]];
	[self addSetPropertyRule:@"url" forPrefix:[self extendPrefix:prefix withValue:@"url"]];
}

- (void) addSetCoordinatePropertyRule:(NSString*)propertyName withPrefix:(NSString*)prefix method:(OBASetCoordinatePropertyMethod)method {
	OBASetCoordinatePropertyJsonDigesterRule * rule = [[OBASetCoordinatePropertyJsonDigesterRule alloc] initWithPropertyName:propertyName method:method];
	[self addRule:rule forPrefix:prefix];
	[rule release];
}

@end
