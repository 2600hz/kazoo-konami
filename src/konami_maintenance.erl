%%%-------------------------------------------------------------------
%%% @copyright (C) 2013-2014, 2600Hz
%%% @doc
%%%
%%% @end
%%% @contributors
%%%-------------------------------------------------------------------
-module(konami_maintenance).

-export([is_running/0
         ,add_default_metaflow/0
         ,add_default_account_metaflow/1
        ]).

-include("konami.hrl").

is_running() ->
    case lists:keyfind('konami', 1, application:which_applications()) of
        'false' -> io:format("Konami is not currently running on this node~n", []);
        {_App, _Desc, _Vsn} ->
            io:format("Konami (~s) is running~n", [_Vsn])
    end.

add_default_metaflow() ->
    Default = whapps_config:get(<<"metaflows">>, <<"default_metaflow">>, wh_json:new()),
    io:format("Welcome to the Default System Metaflow builder~n"),
    intro_builder(Default, fun(JObj) ->
                                   whapps_config:set_default(<<"metaflows">>, <<"default_metaflow">>, JObj)
                           end).

add_default_account_metaflow(AccountId) ->
    Default = whapps_account_config:get(AccountId, <<"metaflows">>, <<"default_metaflow">>, wh_json:new()),
    io:format("Welcome to the Default Account Metaflow builder for ~s~n", [AccountId]),
    intro_builder(Default, fun(JObj) ->
                                   whapps_account_config:set(AccountId, <<"metaflows">>, <<"default_metaflow">>, JObj)
                           end).

intro_builder(Default, SaveFun) ->
    wh_util:ensure_started('konami'),
    io:format("The current default metaflow:~n"),
    io:format("  Binding Digit: ~s~n"
              ,[wh_json:get_value(<<"binding_digit">>, Default, konami_config:binding_digit())]
             ),
    io:format("  Digit Timeout(ms): ~b~n"
              ,[wh_json:get_integer_value(<<"digit_timeout_ms">>, Default, konami_config:timeout())]
             ),

    io:format("  Numbers: ~s~n", [wh_json:encode(wh_json:get_value(<<"numbers">>, Default, wh_json:new()))]),
    io:format("  Patterns: ~s~n~n", [wh_json:encode(wh_json:get_value(<<"patterns">>, Default, wh_json:new()))]),

    menu_builder(Default, SaveFun).

menu_builder(Default, SaveFun) ->
    io:format("1. Change Binding Digit~n"
              "2. Change Digit Timeout~n"
              "3. Change Numbers~n"
              "4. Change Patterns~n"
              "5. Show Current Defaults~n"
              "6. Save~n"
              "7. Exit~n~n"
              ,[]),
    {'ok', [Option]} = io:fread("Which action: ", "~d"),
    menu_builder_action(Default, SaveFun, Option).

menu_builder_action(Default, SaveFun, 1) ->
    {'ok', [BindingDigit]} = io:fread("New binding digit: ", "~s"),
    menu_builder(wh_json:set_value(<<"binding_digit">>, BindingDigit, Default), SaveFun);
menu_builder_action(Default, SaveFun, 2) ->
    {'ok', [DigitTimeout]} = io:fread("New digit timeout (ms): ", "~d"),
    menu_builder(wh_json:set_value(<<"digit_timeout_ms">>, DigitTimeout, Default), SaveFun);
menu_builder_action(Default, SaveFun, 3) ->
    number_builder(Default, SaveFun);
menu_builder_action(Default, SaveFun, 4) ->
    pattern_builder(Default, SaveFun);
menu_builder_action(Default, SaveFun, 5) ->
    intro_builder(Default, SaveFun);
menu_builder_action(Default, SaveFun, 6) ->
    case SaveFun(Default) of
        {'ok', _} ->
            io:format("Defaults successfully saved!~n~n"),
            intro_builder(Default, SaveFun);
        {'error', E} ->
            io:format("failed to save defaults: ~p~n", [E]),
            menu_builder(Default, SaveFun)
    end;
menu_builder_action(_Default, _SaveFun, 7) ->
    'ok';
menu_builder_action(Default, SaveFun, _) ->
    io:format("Action not recognized!~n~n"),
    menu_builder(Default, SaveFun).

number_builder(Default, SaveFun) ->
    Ms = builder_modules('number_builder'),
    number_builder_menu(Default, SaveFun, lists:zip(lists:seq(1, length(Ms)), Ms)).

number_builder_menu(Default, SaveFun, Builders) ->
    io:format("Number Builders:~n", []),

    [io:format("  ~b. ~s~n", [N, builder_name(M)]) || {N, M} <- Builders],
    io:format("  0. Return to Menu~n~n", []),

    {'ok', [Option]} = io:fread("Which builder to add: ", "~d"),
    number_builder_action(Default, SaveFun, Builders, Option).

-spec builder_name(ne_binary() | atom()) -> ne_binary().
builder_name(<<"konami_", Name/binary>>) -> wh_util:ucfirst_binary(Name);
builder_name(<<_/binary>> = Name) -> wh_util:ucfirst_binary(Name);
builder_name(M) -> builder_name(wh_util:to_binary(M)).

number_builder_action(Default, SaveFun, _Builders, 0) ->
    menu_builder(Default, SaveFun);
number_builder_action(Default, SaveFun, Builders, N) ->
    case lists:keyfind(N, 1, Builders) of
        'false' ->
            io:format("invalid option selected~n", []),
            number_builder_menu(Default, SaveFun, Builders);
        {_, Module} ->
            try Module:number_builder(Default) of
                NewDefault ->
                    io:format("  Numbers: ~s~n~n", [wh_json:encode(wh_json:get_value(<<"numbers">>, NewDefault, wh_json:new()))]),
                    number_builder_menu(NewDefault, SaveFun, Builders)
            catch
                _E:_R ->
                    io:format("failed to build number metaflow for ~s~n", [Module]),
                    io:format("~s: ~p~n~n", [_E, _R]),
                    number_builder_menu(Default, SaveFun, Builders)
            end
    end.

pattern_builder(_Default, _SaveFun) ->
    'ok'.

-spec builder_modules(atom()) -> atoms().
builder_modules(F) ->
    {'ok', Modules} = application:get_key('konami', 'modules'),
    [M || M <- Modules, is_builder_module(M, F)].

-spec is_builder_module(atom(), atom()) -> boolean().
is_builder_module(M, F) ->
    try M:module_info('exports') of
        Exports -> props:get_value(F, Exports) =:= 1
    catch
        _E:_R -> 'false'
    end.
