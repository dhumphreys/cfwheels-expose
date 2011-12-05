<cfcomponent output="false" mixin="controller">
	<cffunction name="init" returntype="struct" access="public">
		<cfscript>
			this.version = "1.1,1.2";
			return this;
		</cfscript>
	</cffunction>
	
	<cffunction name="expose" returntype="void" access="public" output="false" hint="Create a new getter function with standard lookup behavior and request caching">
		<cfargument name="name" type="string" required="true" hint="Name of exposed method to register" />
		<cfargument name="override" type="any" required="false" hint="Override behavior. May be a method, relation, or exec string" />
		<cfargument name="model" type="string" required="false" hint="Override model to use in expose" />
		<cfargument name="parent" type="string" required="false" hint="Name of a parent expose function to use for looking up this record" />
		<cfargument name="relation" type="any" required="false" hint="Set a relation to use for query logic" />
		<cfargument name="method" type="any" required="false" hint="Set a method to use for query logic" />
		<cfargument name="exec" type="string" required="false" hint="Set a string to execute for query logic" />
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
			variables[arguments.name] = variables.$exposedMethodHandler;
		</cfscript>
	</cffunction>
	
	<cffunction name="$exposedMethods" returntype="struct" access="public" output="false" hint="Helper to access exposed method for this controller">
		<cfscript>
			if (NOT StructKeyExists(variables.$class, "exposedMethods"))
				variables.$class.exposedMethods = {};
			return variables.$class.exposedMethods;
		</cfscript>
	</cffunction>
	
	<cffunction name="$exposedMethodCache" returntype="struct" access="public" output="false" hint="Helper to access cached exposed method calls for this request">
		<cfscript>
			if (NOT StructKeyExists(request, "$exposedMethodCache"))
				request.$exposedMethodCache = {};
			return request.$exposedMethodCache;
		</cfscript>
	</cffunction>
	
	<cffunction name="$registerExposedMethods" returntype="void" access="public" output="false" hint="Filter to set up exposed methods for control execution">
		<cfscript>
			var key = "";
			for (key in $exposedMethods())
				this[key] = variables[key] = variables.$exposedMethodHandler;
		</cfscript>
	</cffunction>
	
	<cffunction name="$exposedMethodHandler" returntype="any" access="public" output="false" hint="Wrapper for exposed that intelligently determines the called function name">
		<cfargument name="throwErrors" type="boolean" default="true" hint="Pass false to keep missing record errors from being thrown" />
		<cfreturn $runExposedMethod(name=GetFunctionCalledName(), argumentCollection=arguments) />
	</cffunction>
	
	<cffunction name="$runExposedMethod" returntype="any" access="public" output="false" hint="Method body for exposed methods. Lazily loads requested data set and returns it.">
		<cfargument name="name" type="string" required="true" hint="Name of exposed function to call" />
		<cfargument name="throwErrors" type="boolean" default="true" hint="Pass false to keep missing record errors from being thrown" />
		<cfscript>
			var loc = {};
			loc.cache = $exposedMethodCache();
			
			// if method has not be ran yet
			if (NOT StructKeyExists(loc.cache, arguments.name)) {
				loc.params = $exposedMethods()[arguments.name];
			
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
						loc.key = $getExposedMethodKey(arguments.name);
						
						// if there is a parent object set, use the parent as a scope
						if (StructKeyExists(loc.params, "parent")) {
							loc.scope = $runExposedMethod(name=loc.params.parent);
							
							// if the return is false or a new object, return false
							if (NOT IsObject(loc.scope) OR loc.scope.isNew()) {
								loc.returnVal = false;
							} else {
								
								// look up child object
								loc.returnVal = Evaluate("loc.scope.#arguments.name#()");
								
								// if the record was not found, set up a new one
								if (NOT IsObject(loc.returnVal))
									loc.returnVal = Evaluate("loc.scope.new#arguments.name#()");
							}
						
						// if key specified, try looking up record
						} else if (loc.key NEQ false) {
							loc.returnVal = model(loc.params.model).findByKey(params[loc.key]);
							
							// if record was not found, error out
							if (NOT IsObject(loc.returnVal) AND arguments.throwErrors)
								$throw(type="Wheels.RecordNotFound", message="Could not find record where `#loc.key# = #params[loc.key]#`");
							
						// otherwise, create a new model instance
						} else {
							loc.returnVal = model(loc.params.model).new();
						}
							
						// if properties were sent in url, set them in the model
						if (IsObject(loc.returnVal) AND StructKeyExists(params, arguments.name))
							loc.returnVal.setProperties(params[arguments.name]);
							
						break;
					
					// look up a collection of records
					default:
						loc.returnVal = model(loc.params.model).findAll();
				}
				
				// cache return value
				loc.cache[arguments.name] = loc.returnVal;
			}
			
			return loc.cache[arguments.name];
		</cfscript>
	</cffunction>
	
	<cffunction name="$getExposedMethodKey" returntype="any" access="public" output="false" hint="Helper to get name of params key that should be used to look up instance">
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
	
	<cffunction name="$getObject" returntype="any" access="public" output="false" hint="Override wheels function so that exposed methods can be referenced in form helpers">
		<cfargument name="objectName" type="string" required="true">
		<cfscript>
			var loc = {};
			loc.returnVal = loc[objectName] = core.$getObject(argumentCollection=arguments);
			
			// if the value returned is a function, call it and return
			if (IsCustomFunction(loc.returnVal))
				return Evaluate("loc.#objectName#()");
			
			return loc.returnVal;
		</cfscript>
	</cffunction>
</cfcomponent>