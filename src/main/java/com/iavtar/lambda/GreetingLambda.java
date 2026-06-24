package com.iavtar.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import jakarta.inject.Named;

@Named("greeting")
public class GreetingLambda implements RequestHandler<Person, String> {

    @Override
    public String handleRequest(Person input, Context context) {
        return "Hello " + input.getName();
    }
}
