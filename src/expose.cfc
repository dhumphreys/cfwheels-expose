<cfcomponent output="false" mixin="controller">
	<cffunction name="init" returntype="struct" access="public">
		<cfscript>
			this.version = "1.1,1.2";
			return this;
		</cfscript>
	</cffunction>
	
	<cffunction name="expose" returntype="void" access="public">
		<cfargument name="name" type="string" required="true" />
		<cfargument name="override" type="any" required="false" />
		<cfargument name="model" type="string" required="false" />
		<cfargument name="relation" type="any" required="false" />
		<cfargument name="method" type="any" required="false" />
		<cfargument name="exec" type="string" required="false" />
		<cfscript>
			var loc = {};
			
			// set up before filter to create exposed methods at runtime
			if (NOT StructKeyExists(variables.$class, "hasExposedMethods")) {
				filters(through="$registerExposedMethods");
				variables.$class.hasExposedMethods = true;
			}
			
			// if 'override' passed in, set up arguments based on type
			if (StructKeyExists(arguments, "override")) {
				if (IsCustomFunction(arguments.override))
					arguments.method = arguments.override;
				else if (IsSimpleValue(arguments.override))
					arguments.exec = arguments.override;
				StructDelete(arguments, "override");
			}
			
			// get model name if not defined
			if (NOT StructKeyExists(arguments, "model"))
				arguments.model = singularize(arguments.name);
				
			// determine type of exposed method
			if (StructKeyExists(arguments, "exec"))
				arguments.type = "exec";
			else if (StructKeyExists(arguments, "method"))
				arguments.type = "method";
			else if (StructKeyExists(arguments, "relation"))
				arguments.type = "relation";
			else if (arguments.name EQ pluralize(arguments.name))
				arguments.type = "plural";
			else
				arguments.type = "singular";
			
			// store exposed methods
			loc.exposedMethods = $exposedMethods();
			loc.exposedMethods[arguments.name] = arguments;
			
			// set exposed method
			variables[arguments.name] = variables.$runExposedMethod;
		</cfscript>
	</cffunction>
	
	<cffunction name="$exposedMethods" returntype="struct" access="public">
		<cfscript>
			if (NOT StructKeyExists(variables.$class, "exposedMethods"))
				variables.$class.exposedMethods = {};
			return variables.$class.exposedMethods;
		</cfscript>
	</cffunction>
	
	<cffunction name="$exposedMethodCache" returntype="struct" access="public">
		<cfscript>
			if (NOT StructKeyExists(request, "$exposedMethodCache"))
				request.$exposedMethodCache = {};
			return request.$exposedMethodCache;
		</cfscript>
	</cffunction>
	
	<cffunction name="$registerExposedMethods" returntype="void" access="public">
		<cfscript>
			var key = "";
			for (key in $exposedMethods())
				variables[key] = variables.$runExposedMethod;
		</cfscript>
	</cffunction>
	
	<cffunction name="$runExposedMethod" returntype="any" access="public">
		<cfscript>
			var loc = {};
			loc.name = GetFunctionCalledName();
			loc.cache = $exposedMethodCache();
			
			// if method has not be ran yet
			if (NOT StructKeyExists(loc.cache, loc.name)) {
				loc.params = $exposedMethods()[loc.name];
			
				// trigger appropriate method behavior
				switch(loc.params.type) {
					
					// execute a coldfusion statement
					case "exec":
						loc.returnVal = Evaluate(loc.params.exec);
						break;
						
					// execute a method
					case "method":
						var customMethod = loc.params.method;
						loc.returnVal = customMethod();
						break;
						
					// try to look up a single record
					case "singular":
						loc.key = $getExposedMethodKey(loc.name);
						
						// if key specified, try looking up record
						if (loc.key NEQ false) {
							loc.returnVal = model(loc.params.model).findByKey(params[loc.key]);
							
							// if record was not found, error out
							if (NOT IsObject(loc.returnVal))
								$throw(type="Wheels.RecordNotFound", message="Could not find record where `#loc.key# = #params[loc.key]#`");
							
							// if properties sent in url, set them in the model
							if (StructKeyExists(params, loc.name))
								loc.returnVal.setProperties(params[loc.name]);
							
						// otherwise, create a new model instance
						} else {
							loc.properties = StructKeyExists(params, loc.name) ? params[loc.name] : {};
							loc.returnVal = model(loc.params.model).new(loc.properties);
						}
						break;
					
					// look up a collection of records
					default:
						loc.returnVal = model(loc.params.model).findAll();
				}
				
				// cache return value
				loc.cache[loc.name] = loc.returnVal;
			}
			
			return loc.cache[loc.name];
		</cfscript>
	</cffunction>
	
	<cffunction name="$getExposedMethodKey" returntype="any" access="public">
		<cfargument name="name" type="string" required="true" />
		<cfscript>
			var namedKey = name & "Key";
			if (StructKeyExists(params, namedKey))
				return namedKey;
			else if (StructKeyExists(params, "key"))
				return "key";
			return false;
		</cfscript>
	</cffunction>
	
	<cffunction name="$getObject" returntype="any" access="public">
		<cfargument name="objectName" type="string" required="true">
		<cfscript>
			var loc = {};
			loc.returnVal = loc[objectName] = core.$getObject(argumentCollection=arguments);
			if (IsCustomFunction(loc.returnVal))
				return Evaluate("loc.#objectName#()");
			return loc.returnVal;
		</cfscript>
	</cffunction>
</cfcomponent>