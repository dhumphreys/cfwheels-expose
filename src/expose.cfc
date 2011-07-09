<cfcomponent output="false" mixin="controller">
	<cffunction name="init" returntype="struct" access="public">
		<cfscript>
			this.version = "1.1,1.2";
			return this;
		</cfscript>
	</cffunction>
	
	<cffunction name="expose" returntype="void" access="public">
		<cfargument name="name" type="string" required="true" />
		<cfargument name="model" type="string" required="false" />
		<cfargument name="relation" type="any" required="false" />
		<cfargument name="method" type="string" required="false" />
		<cfargument name="exec" type="string" required="false" />
		<cfscript>
			var loc = {};
			
			// set up before filter to create exposed methods at runtime
			if (NOT StructKeyExists(variables.$class, "hasExposedMethods")) {
				filters(through="$registerExposedMethods");
				variables.$class.hasExposedMethods = true;
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
				
				// look up named key for url params
				loc.namedKey = loc.name & "Key";
			
				// trigger appropriate method behavior
				switch(loc.params.type) {
					case "exec":
						loc.returnVal = Evaluate(loc.params.exec);
						break;
					case "method":
						loc.returnVal = Evaluate("variables.#loc.params.method#()");
						break;
					case "singular":
						if (StructKeyExists(params, loc.namedKey))
							loc.returnVal = model(loc.params.model).findByKey(params[loc.namedKey]);
						else if (StructKeyExists(params, "key"))
							loc.returnVal = model(loc.params.model).findByKey(params.key);
						else if (StructKeyExists(params, loc.name))
							loc.returnVal = model(loc.params.model).new(params[loc.name]);
						else
							loc.returnVal = model(loc.params.model).new();
						break;
					default:
						loc.returnVal = model(loc.params.model).findAll();
				}
				
				// cache return value
				loc.cache[loc.name] = loc.returnVal;
			}
			
			return loc.cache[loc.name];
		</cfscript>
	</cffunction>
</cfcomponent>