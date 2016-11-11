#import "DDXMLPrivate.h"
#import "NSString+DDXML.h"
#import "NSString+HTML.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Welcome to KissXML.
 * 
 * The project page has documentation if you have questions.
 * https://github.com/robbiehanson/KissXML
 * 
 * If you're new to the project you may wish to read the "Getting Started" wiki.
 * https://github.com/robbiehanson/KissXML/wiki/GettingStarted
 * 
 * KissXML provides a drop-in replacement for Apple's NSXML class cluster.
 * The goal is to get the exact same behavior as the NSXML classes.
 * 
 * For API Reference, see Apple's excellent documentation,
 * either via Xcode's Mac OS X documentation, or via the web:
 * 
 * https://github.com/robbiehanson/KissXML/wiki/Reference
**/

@interface DDXMLDocument ()

- (void)parseNodeFromDictionary:(NSDictionary*)dictionary atNode:(xmlNodePtr)node;

@end

@implementation DDXMLDocument

/**
 * Returns a DDXML wrapper object for the given primitive node.
 * The given node MUST be non-NULL and of the proper type.
**/
+ (id)nodeWithDocPrimitive:(xmlDocPtr)doc owner:(DDXMLNode *)owner
{
	return [[DDXMLDocument alloc] initWithDocPrimitive:doc owner:owner];
}

- (id)initWithDocPrimitive:(xmlDocPtr)doc owner:(DDXMLNode *)inOwner
{
	self = [super initWithPrimitive:(xmlKindPtr)doc owner:inOwner];
	return self;
}

+ (id)nodeWithPrimitive:(xmlKindPtr)kindPtr owner:(DDXMLNode *)owner
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes
	NSAssert(NO, @"Use nodeWithDocPrimitive:owner:");
	
	return nil;
}

- (id)initWithPrimitive:(xmlKindPtr)kindPtr owner:(DDXMLNode *)inOwner
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes.
	NSAssert(NO, @"Use initWithDocPrimitive:owner:");
	
	return nil;
}

/**
 * Initializes and returns a DDXMLDocument object created from an NSData object.
 * 
 * Returns an initialized DDXMLDocument object, or nil if initialization fails
 * because of parsing errors or other reasons.
**/
- (id)initWithXMLString:(NSString *)string options:(NSUInteger)mask error:(NSError **)error
{
	return [self initWithData:[string dataUsingEncoding:NSUTF8StringEncoding]
	                  options:mask
	                    error:error];
}

/**
 * Initializes and returns a DDXMLDocument object created from an NSData object.
 * 
 * Returns an initialized DDXMLDocument object, or nil if initialization fails
 * because of parsing errors or other reasons.
**/
- (id)initWithData:(NSData *)data options:(NSUInteger)mask error:(NSError **)error
{
	if (data == nil || [data length] == 0)
	{
		if (error) *error = [NSError errorWithDomain:@"DDXMLErrorDomain" code:0 userInfo:nil];
		
		return nil;
	}
	
	// Even though xmlKeepBlanksDefault(0) is called in DDXMLNode's initialize method,
	// it has been documented that this call seems to get reset on the iPhone:
	// http://code.google.com/p/kissxml/issues/detail?id=8
	// 
	// Therefore, we call it again here just to be safe.
	xmlKeepBlanksDefault(0);
    //
    //NSLog(@"DDXMLDocument - initWithData : %@", [NSString stringWithCString:[data bytes] encoding:NSUTF8StringEncoding]);
	
	xmlDocPtr doc = xmlParseMemory([data bytes], (int)[data length]);
	if (doc == NULL)
	{
		if (error) *error = [NSError errorWithDomain:@"DDXMLErrorDomain" code:1 userInfo:nil];
		
		return nil;
	}
	
	return [self initWithDocPrimitive:doc owner:nil];
}

- (id)initWithDictionary:(NSDictionary *)dictionary options:(NSUInteger)mask error:(NSError **)error
{
    xmlDocPtr doc       = xmlNewDoc((const xmlChar*)"1.0");
    
    // Top level dictionary within the specified dictionary is the root node
    for (NSObject* topKey in dictionary)
    {
        NSAssert(xmlDocGetRootElement(doc) == 0, @"an xml document can only have one root!");
        NSAssert([topKey isKindOfClass:[NSString class]], @"all dictionary keys must be strings!");
        
        NSString* topKeyString = (NSString*)topKey;
        
        xmlNodePtr rootNode = xmlNewNode(NULL, (const xmlChar*)[topKeyString cStringUsingEncoding:NSUTF8StringEncoding]);
        xmlDocSetRootElement(doc, rootNode);
        
        NSObject* topObject = [dictionary objectForKey:topKey];
        NSAssert([topObject isKindOfClass:[NSDictionary class]], @"top dictionary object must be a dictionary!");
        
        [self parseNodeFromDictionary:(NSDictionary*)topObject atNode:rootNode];
    }
             
    return [self initWithDocPrimitive:doc owner:nil];
}

- (void)dealloc
{
}

/**
 * Returns the root element of the receiver.
**/
- (DDXMLElement *)rootElement
{
#if DDXML_DEBUG_MEMORY_ISSUES
	DDXMLNotZombieAssert();
#endif
	
	xmlDocPtr doc = (xmlDocPtr)genericPtr;
	
	// doc->children is a list containing possibly comments, DTDs, etc...
	
	xmlNodePtr rootNode = xmlDocGetRootElement(doc);
	
	if (rootNode != NULL)
		return [DDXMLElement nodeWithElementPrimitive:rootNode owner:self];
	else
		return nil;
}

- (NSData *)XMLData
{
	// Zombie test occurs in XMLString
	return [[self XMLString] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)XMLDataWithOptions:(NSUInteger)options
{
	// Zombie test occurs in XMLString
	return [[self XMLStringWithOptions:options] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSDictionary*)dictionary
{
    DDXMLElement* rootElement       = [self rootElement];
    return [rootElement elements]; 
}

- (void)parseNodeFromDictionary:(NSDictionary*)dictionary atNode:(xmlNodePtr)parentNode
{
    for (NSObject* key in dictionary)
    {
        NSAssert([key isKindOfClass:[NSString class]], @"all dictionary keys must be strings!");
        
        NSString* keyString = (NSString*)key;
        NSObject *object = [dictionary objectForKey:key];
        
        if ([object isKindOfClass:[NSDictionary class]])
        {
            xmlNodePtr childNode = xmlNewNode(NULL, (const xmlChar*)[keyString cStringUsingEncoding:NSUTF8StringEncoding]);
            [self parseNodeFromDictionary:(NSDictionary*)object atNode:childNode];
            xmlAddChild(parentNode, childNode);
        }
        else if ([object isKindOfClass:[NSString class]])
        {
            NSString* contentString = [NSString stringWithFormat:@"%@", (NSString*)object];
            
            // Check if the parameter is an attribute
            if ([keyString hasSuffix:@"=__attribute__"])
            {
                //xmlNewProp(parentNode, BAD_CAST "attribute", BAD_CAST "yes");
                
                NSString* attributeName = [keyString substringToIndex:[keyString rangeOfString:@"=__attribute__"].location];
                NSString* escapedContentString = [contentString htmlEscapedString];
                xmlNewProp(parentNode,
                           BAD_CAST [attributeName cStringUsingEncoding:NSUTF8StringEncoding], 
                           BAD_CAST [escapedContentString cStringUsingEncoding:NSUTF8StringEncoding]);
            }
            else 
            {
                NSString* escapedContentString = [contentString htmlEscapedString];
                xmlNewChild(parentNode, NULL,
                            BAD_CAST [keyString cStringUsingEncoding:NSUTF8StringEncoding], 
                            BAD_CAST [escapedContentString cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        }
        else if ([object isKindOfClass:[NSNumber class]])
        {
            NSNumber* contentNumber = (NSNumber*)object;
            xmlNewChild(parentNode, NULL, 
                        BAD_CAST [keyString cStringUsingEncoding:NSUTF8StringEncoding], 
                        BAD_CAST [[contentNumber stringValue] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        else if ([object isKindOfClass:[NSArray class]])
        {
            // Compose list of dictionary tags from the array of objects
            NSArray* array = (NSArray*)object;
            for (NSObject* object in array)
            {
//                [object isKindOfClass:[NSString class]]
                if ([object isKindOfClass:[NSDictionary class]])
                {
                    xmlNodePtr childNode = xmlNewNode(NULL, (const xmlChar*)[keyString cStringUsingEncoding:NSUTF8StringEncoding]);
                    [self parseNodeFromDictionary:(NSDictionary*)object atNode:childNode];
                    xmlAddChild(parentNode, childNode);
                }
                else if ([object isKindOfClass:[NSString class]])
                {
                    NSString* contentString = [NSString stringWithFormat:@"%@", (NSString*)object];
                    NSString* escapedContentString = [contentString htmlEscapedString];
                    xmlNewChild(parentNode, NULL,
                                BAD_CAST [keyString cStringUsingEncoding:NSUTF8StringEncoding],
                                BAD_CAST [escapedContentString cStringUsingEncoding:NSUTF8StringEncoding]);
                }
                //NSAssert(, @"all objects in an array need to be a dictionary!");
            }
        }
    }
}

@end
