@RestResource(urlMapping='/wrapper/*')
global with sharing class WrapperREST {
    @HttpPost
    global static void dispatchPost() {
        dispatch(RestContext.request, RestContext.response);
    }

    @HttpGet
    global static void dispatchGet() {
        dispatch(RestContext.request, RestContext.response);
    }
    
    private static void dispatch(RestRequest request, RestResponse response) {
        String path = request.requestURI;

        if (path == '/wrapper' || path == '/wrapper/') {
            handlerIndex(request, response);
        } else if (path == '/wrapper/track') {
            handlerTrack(request, response);
        } else if (path == '/wrapper/identify') {
            handlerIdentify(request, response);
        } else if (path == '/wrapper/allFlags') {
            handlerAllFlags(request, response);
        } else if (path.startsWith('/wrapper/feature/')) {
            handlerEval(request, response);
        } else if (path.startsWith('/wrapper/flush')) {
            response.statusCode = 200;
        } else {
            response.statusCode = 404;
        }
    }

    private static void handlerIndex(RestRequest request, RestResponse response) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('initialized', true);
        result.put('baseUri', 'https://ld-stg.launchdarkly.com');
        result.put('streamUri', 'https://stream-stg.launchdarkly.com');
        result.put('eventsUri', 'https://events-stg.launchdarkly.com');
        result.put('sdkKeyEndingIn', 'c4f2f');
        result.put('stream', false);
        result.put('upSince', 0);
        result.put('clientVersion', '0.0.0');

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(result));
    }

    private static void handlerTrack(RestRequest request, RestResponse response) {
        Map<String, Object> body = (Map<String, Object>)JSON.deserializeUntyped(request.requestBody.tostring());
        
        LDClient client = buildClient((Object)body);
        LDUser   user   = buildUser((Object)body);
        
        client.track(user, (String)body.get('key'), (Double)body.get('metricValue'), null);

        response.statusCode = 200;
    }

    private static void handlerIdentify(RestRequest request, RestResponse response) {
        Map<String, Object> body = (Map<String, Object>)JSON.deserializeUntyped(request.requestBody.tostring());
        
        LDClient client = buildClient((Object)body);
        LDUser   user   = buildUser((Object)body);
        
        client.identify(user);

        response.statusCode = 200;
    }

    private static void handlerAllFlags(RestRequest request, RestResponse response) {
        Map<String, Object> body = (Map<String, Object>)JSON.deserializeUntyped(request.requestBody.tostring());
        
        LDClient client = buildClient((Object)body);
        LDUser   user   = buildUser((Object)body);
        
        Map<String, LDValue> allFlags = client.allFlags(user);
        Map<String, Object> allFlagsProcessed = new Map<String, Object>();
        
        for (String key : allFlags.keySet()){
            allFlagsProcessed.put(key, allFlags.get(key).toGeneric());
        }

        RestContext.response.statusCode = 200;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(allFlagsProcessed));
    }
    
    private static void handlerEval(RestRequest request, RestResponse response) {
        Map<String, Object> body = (Map<String, Object>)JSON.deserializeUntyped(request.requestBody.tostring());

        LDClient client = buildClient((Object)body);
        LDUser   user   = buildUser((Object)body);
        
        String key = request.requestURI.split('/')[3];
        String valueType = (String)body.get('valueType');
        Boolean detail = (Boolean)body.get('detail');

        Object value;
        LDClient.EvaluationDetail details = new LDClient.EvaluationDetail();

        switch on valueType {
            when 'string' {
                if (detail) {
                    value = (Object)client.stringVariation(user, key, (String)body.get('defaultValue'), details);
                } else {
                    value = (Object)client.stringVariation(user, key, (String)body.get('defaultValue'));
                }
            }
            when 'bool' {
                if (detail) {
                    value = (Object)client.boolVariation(user, key, (Boolean)body.get('defaultValue'), details);
                } else {
                    value = (Object)client.boolVariation(user, key, (Boolean)body.get('defaultValue'));
                }
            }
            when 'float' {
                if (detail) {
                    value = (Object)client.doubleVariation(user, key, (Double)body.get('defaultValue'), details);
                } else {
                    value = (Object)client.doubleVariation(user, key, (Double)body.get('defaultValue'));
                }
            }
            when 'int' {
                if (detail) {
                    value = (Object)client.intVariation(user, key, (Integer)body.get('defaultValue'), details);
                } else {
                    value = (Object)client.intVariation(user, key, (Integer)body.get('defaultValue'));
                }
            }
            when 'json' {
                if (detail) {
                    value = client.jsonVariation(user, key, LDValue.ofGeneric(body.get('defaultValue')), details).toGeneric();
                } else {
                    value = client.jsonVariation(user, key, LDValue.ofGeneric(body.get('defaultValue'))).toGeneric();
                }
            }
            when else {
                RestContext.response.statusCode = 400;

                return;
            }
        }
        
        Map<String, Object> result = new Map<String, Object>();
        result.put('result', value);
        
        if (detail == true) {
            result.put('reason', details.getReason().toGeneric());
            result.put('variationIndex', details.getVariationIndex());
        }

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(result));
    }
    
    private static LDClient buildClient(Object body) {
        Map<String, Object> bodyMap = (Map<String, Object>)body;

        LDConfig.Builder builder = new LDConfig.Builder('sdk-xyz');

        if (bodyMap.get('allAttributesPrivate') == true) {
            builder.setAllAttributesPrivate(true);
        }

        return new LDClient(builder.build());
    }
    
    private static LDUser buildUser(Object body) {
        Map<String, Object> bodyMap = (Map<String, Object>)body;
        Map<String, Object> userMap = (Map<String, Object>)bodyMap.get('user');
        
        LDUser.Builder builder = new LDUser.Builder((String)userMap.get('key'))
            .setIP((String)userMap.get('ip'))
            .setFirstName((String)userMap.get('firstName'))
            .setLastName((String)userMap.get('lastName'))
            .setEmail((String)userMap.get('email'))
            .setName((String)userMap.get('name'))
            .setAvatar((String)userMap.get('avatar'))
            .setCountry((String)userMap.get('country'))
            .setSecondary((String)userMap.get('secondary'))
            .setAnonymous((Boolean)userMap.get('anonymous'));

        if (bodyMap.get('privateAttributeNames') != null) {
            List<Object> privateAttributeNamesGeneric = (List<Object>)bodyMap.get('privateAttributeNames');

            Set<String> privateAttributeNames = new Set<String>();
            
            for (Object privateAttributeNameGeneric : privateAttributeNamesGeneric) {
                privateAttributeNames.add((String)privateAttributeNameGeneric);
            }

            builder.setPrivateAttributeNames(privateAttributeNames);
        }
        
        if (userMap.get('custom') != null) {
            builder.setCustom((LDValueObject)LDValue.ofGeneric(userMap.get('custom')));
        }

        return builder.build();
    }
}
