//
//  CustomView1.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView1: View {
    @State public var text1Text: String = "Hottest Banker in H.K."
    @State public var text2Text: String = "Corporate Poll"
    @State public var image1Path: String = "image1_I426841881"
    @State public var text3Text: String = "1"
    @State public var text4Text: String = "Lucy Liu"
    @State public var text5Text: String = "Morgan Stanley"
    @State public var text6Text: String = "2293"
    @State public var image7Path: String = "image7_I426841901"
    @State public var text7Text: String = "2"
    @State public var text8Text: String = "Lucy Liu"
    @State public var text9Text: String = "Morgan Stanley"
    @State public var text10Text: String = "2293"
    @State public var image13Path: String = "image13_I426841921"
    @State public var text11Text: String = "3"
    @State public var text12Text: String = "Lucy Liu"
    @State public var text13Text: String = "Morgan Stanley"
    @State public var text14Text: String = "2293"
    @State public var image19Path: String = "image19_I426841941"
    @State public var text15Text: String = "4"
    @State public var text16Text: String = "Lucy Liu"
    @State public var text17Text: String = "Morgan Stanley"
    @State public var text18Text: String = "2293"
    @State public var image25Path: String = "image25_I426841961"
    @State public var text19Text: String = "5"
    @State public var text20Text: String = "Lucy Liu"
    @State public var text21Text: String = "Morgan Stanley"
    @State public var text22Text: String = "2293"
    @State public var text23Text: String = "view more"
    @State public var image31Path: String = "image31_4274"
    @State public var image32Path: String = "image32_4275"
    @State public var text24Text: String = "Simone Carter"
    @State public var text25Text: String = "1d"
    @State public var image33Path: String = "image33_4282"
    @State public var image34Path: String = "image34_4283"
    @State public var image35Path: String = "image35_4291"
    @State public var text26Text: String = "93"
    @State public var text27Text: String = "kyleegigstead Cyborg dreams"
    @State public var text28Text: String = "kyleegigstead Cyborg dreams"
    @State public var image36Path: String = "image36_4298"
    @State public var image37Path: String = "image37_4304"
    @State public var image38Path: String = "image38_4305"
    @State public var text29Text: String = "Simone Carter"
    @State public var text30Text: String = "1d"
    @State public var image39Path: String = "image39_4312"
    @State public var image40Path: String = "image40_4313"
    @State public var image41Path: String = "image41_4321"
    @State public var text31Text: String = "93"
    @State public var text32Text: String = "kyleegigstead Cyborg dreams"
    @State public var text33Text: String = "kyleegigstead Cyborg dreams"
    @State public var image42Path: String = "image42_4328"
    @State public var image43Path: String = "image43_4334"
    @State public var image44Path: String = "image44_4335"
    @State public var text34Text: String = "Simone Carter"
    @State public var text35Text: String = "1d"
    @State public var image45Path: String = "image45_4342"
    @State public var image46Path: String = "image46_4343"
    @State public var image47Path: String = "image47_4351"
    @State public var text36Text: String = "93"
    @State public var text37Text: String = "kyleegigstead Cyborg dreams"
    @State public var text38Text: String = "kyleegigstead Cyborg dreams"
    @State public var image48Path: String = "image48_4358"
    @State public var image49Path: String = "image49_4363"
    @State public var image50Path: String = "image50_4369"
    @State public var image51Path: String = "image51_4370"
    @State public var image52Path: String = "image52_4372"
    @State public var image53Path: String = "image53_4373"
    @State public var image54Path: String = "image54_4374"
    @State public var image55Path: String = "image55_4376"
    @State public var image56Path: String = "image56_4378"
    @State public var image57Path: String = "image57_4380"
    @State public var image58Path: String = "image58_4382"
    @State public var text39Text: String = "Message"
    @State public var image59Path: String = "image59_4385"
    @State public var text40Text: String = "Account"
    @State public var image60Path: String = "image60_4388"
    @State public var text41Text: String = "Home"
    @State public var image61Path: String = "image61_4393"
    @State public var image62Path: String = "image62_4395"
    @State public var image63Path: String = "image63_4398"
    @State public var image64Path: String = "image64_4399"
    @State public var image65Path: String = "image65_4401"
    @State public var image66Path: String = "image66_4403"
    @State public var image67Path: String = "image67_I44044382"
    @State public var text42Text: String = "Message"
    @State public var text43Text: String = "Account"
    @State public var image68Path: String = "image68_4406"
    @State public var image69Path: String = "image69_4409"
    @State public var text44Text: String = "Home"
    @State public var text45Text: String = "Bruce Li"
    @State public var image70Path: String = "image70_I441241875"
    @State public var image71Path: String = "image71_4413"
    @State public var image72Path: String = "image72_4415"
    @State public var text46Text: String = "Posts"
    @State public var text47Text: String = "Saved"
    @State public var text48Text: String = "Liked"
    @State public var image73Path: String = "image73_4423"
    @State public var text49Text: String = "Bruce Li"
    @State public var text50Text: String = "China"
    @State public var text51Text: String = "Following"
    @State public var text52Text: String = "3021"
    @State public var text53Text: String = "Followers"
    @State public var text54Text: String = "3021"
    @State public var text55Text: String = "Likes"
    @State public var text56Text: String = "3021"
    @State public var image74Path: String = "image74_4445"
    @State public var image75Path: String = "image75_4446"
    @State public var image76Path: String = "image76_4451"
    @State public var text57Text: String = "William Rhodes"
    @State public var text58Text: String = "10m"
    @State public var image77Path: String = "image77_4455"
    @State public var image78Path: String = "image78_4458"
    @State public var text59Text: String = "kyleegigstead Cyborg dreams"
    @State public var text60Text: String = "kyleegigstead Cyborg dreams"
    @State public var image79Path: String = "image79_4464"
    @State public var text61Text: String = "2293"
    @State public var image80Path: String = "image80_4474"
    @State public var text62Text: String = "William Rhodes"
    @State public var text63Text: String = "10m"
    @State public var image81Path: String = "image81_4478"
    @State public var image82Path: String = "image82_4481"
    @State public var text64Text: String = "kyleegigstead Cyborg dreams"
    @State public var text65Text: String = "kyleegigstead Cyborg dreams"
    @State public var image83Path: String = "image83_4487"
    @State public var text66Text: String = "2293"
    @State public var text67Text: String = "Edit profile"
    @State public var text68Text: String = "Share profile"
    @State public var image84Path: String = "image84_4498"
    @State public var text69Text: String = "Bruce Li"
    @State public var image85Path: String = "image85_I450441875"
    @State public var image86Path: String = "image86_4505"
    @State public var image87Path: String = "image87_4508"
    @State public var text70Text: String = "Edit profile"
    @State public var image88Path: String = "image88_4511"
    @State public var image89Path: String = "image89_4513"
    @State public var text71Text: String = "Bruce Li"
    @State public var image90Path: String = "image90_I451641875"
    @State public var image91Path: String = "image91_4517"
    @State public var image92Path: String = "image92_4520"
    @State public var text72Text: String = "Favorite"
    @State public var image93Path: String = "image93_4523"
    @State public var image94Path: String = "image94_4525"
    @State public var image95Path: String = "image95_4527"
    @State public var image96Path: String = "image96_4530"
    @State public var text73Text: String = "Received likes and collected "
    @State public var image97Path: String = "image97_4540"
    @State public var text74Text: String = "Number of posts"
    @State public var text75Text: String = "30"
    @State public var image98Path: String = "image98_4547"
    @State public var text76Text: String = "Gain collection points"
    @State public var text77Text: String = "479"
    @State public var image99Path: String = "image99_4554"
    @State public var text78Text: String = "Get the number of likes"
    @State public var text79Text: String = "61"
    @State public var text80Text: String = "OK"
    @State public var text81Text: String = "Bruce Li"
    @State public var image100Path: String = "image100_I456341875"
    @State public var image101Path: String = "image101_4564"
    @State public var image102Path: String = "image102_4567"
    @State public var text82Text: String = "Share profile"
    @State public var image103Path: String = "image103_4570"
    @State public var image104Path: String = "image104_4572"
    @State public var text83Text: String = "Bruce Li"
    @State public var image105Path: String = "image105_I457541875"
    @State public var image106Path: String = "image106_4576"
    @State public var image107Path: String = "image107_4579"
    @State public var image108Path: String = "image108_4581"
    @State public var image109Path: String = "image109_4583"
    @State public var text84Text: String = "Settings"
    @State public var image110Path: String = "image110_4590"
    @State public var text85Text: String = "Profile Settings"
    @State public var image111Path: String = "image111_4600"
    @State public var image112Path: String = "image112_4604"
    @State public var text86Text: String = "Alias Accounts"
    @State public var image113Path: String = "image113_4614"
    @State public var image114Path: String = "image114_4617"
    @State public var text87Text: String = "Devices"
    @State public var image115Path: String = "image115_4627"
    @State public var image116Path: String = "image116_4630"
    @State public var text88Text: String = "Invite Friends"
    @State public var image117Path: String = "image117_4640"
    @State public var image118Path: String = "image118_4643"
    @State public var text89Text: String = "Sign Out"
    @State public var image119Path: String = "image119_4653"
    @State public var image120Path: String = "image120_4656"
    @State public var text90Text: String = "My Channels"
    @State public var image121Path: String = "image121_4666"
    @State public var image122Path: String = "image122_4669"
    @State public var text91Text: String = "Dark Mode"
    @State public var image123Path: String = "image123_4679"
    @State public var text92Text: String = "Bruce Li"
    @State public var image124Path: String = "image124_I468441875"
    @State public var image125Path: String = "image125_4685"
    @State public var image126Path: String = "image126_4688"
    @State public var image127Path: String = "image127_4690"
    @State public var image128Path: String = "image128_4692"
    @State public var text93Text: String = "Accounts"
    @State public var image129Path: String = "image129_4694"
    @State public var text94Text: String = "You can add or remove accounts in the account center."
    @State public var text95Text: String = "Add an account"
    @State public var image130Path: String = "image130_4699"
    @State public var image131Path: String = "image131_4701"
    @State public var text96Text: String = "Account_one"
    @State public var text97Text: String = "Icered"
    @State public var image132Path: String = "image132_4706"
    @State public var image133Path: String = "image133_4708"
    @State public var text98Text: String = "Account_two"
    @State public var text99Text: String = "Icered"
    @State public var text100Text: String = "Bruce Li"
    @State public var image134Path: String = "image134_I471441875"
    @State public var image135Path: String = "image135_4715"
    @State public var image136Path: String = "image136_4717"
    @State public var image137Path: String = "image137_4719"
    @State public var text101Text: String = "Select the account you wish to add"
    @State public var image138Path: String = "image138_4721"
    @State public var image139Path: String = "image139_4724"
    @State public var text102Text: String = "Add an Icered account"
    @State public var image140Path: String = "image140_4734"
    @State public var image141Path: String = "image141_4736"
    @State public var image142Path: String = "image142_4740"
    @State public var image143Path: String = "image143_4742"
    @State public var text103Text: String = "Icered.com"
    @State public var text104Text: String = "Cancel"
    @State public var text105Text: String = "Log in"
    @State public var text106Text: String = "Password"
    @State public var text107Text: String = "Forget the password ?"
    @State public var text108Text: String = "Telephone, account or email"
    @State public var image144Path: String = "image144_4752"
    @State public var text109Text: String = "Bruce Li"
    @State public var image145Path: String = "image145_I475541875"
    @State public var image146Path: String = "image146_4756"
    @State public var image147Path: String = "image147_4759"
    @State public var image148Path: String = "image148_4761"
    @State public var image149Path: String = "image149_4763"
    @State public var text110Text: String = "Devices"
    @State public var image150Path: String = "image150_4766"
    @State public var text111Text: String = "Apple iPhone17"
    @State public var text112Text: String = "Last active: Invalid Date"
    @State public var image151Path: String = "image151_4771"
    @State public var image152Path: String = "image152_4775"
    @State public var text113Text: String = "Mac"
    @State public var text114Text: String = "Last active: Invalid Date"
    @State public var image153Path: String = "image153_4780"
    @State public var text115Text: String = "Bruce Li"
    @State public var image154Path: String = "image154_I478641875"
    @State public var image155Path: String = "image155_4787"
    @State public var image156Path: String = "image156_4789"
    @State public var image157Path: String = "image157_4791"
    @State public var image158Path: String = "image158_4793"
    @State public var text116Text: String = "Invite Friends"
    @State public var image159Path: String = "image159_I47954952"
    @State public var text117Text: String = "Search"
    @State public var image160Path: String = "image160_I479741093"
    @State public var text118Text: String = "Share invitation link "
    @State public var text119Text: String = "You have 3 invitations left."
    @State public var text120Text: String = "Bruce Li"
    @State public var image161Path: String = "image161_I480141875"
    @State public var image162Path: String = "image162_4802"
    @State public var image163Path: String = "image163_4805"
    @State public var image164Path: String = "image164_4807"
    @State public var image165Path: String = "image165_4809"
    @State public var text121Text: String = "My Channels"
    @State public var text122Text: String = "Bruce Li"
    @State public var image166Path: String = "image166_I481341875"
    @State public var image167Path: String = "image167_4814"
    @State public var image168Path: String = "image168_4817"
    @State public var image169Path: String = "image169_4819"
    @State public var image170Path: String = "image170_4821"
    @State public var text123Text: String = "Profile Setting"
    @State public var text124Text: String = "Save"
    @State public var image171Path: String = "image171_4825"
    @State public var image172Path: String = "image172_4829"
    @State public var text125Text: String = "First name"
    @State public var text126Text: String = "Username"
    @State public var text127Text: String = "Gender"
    @State public var text128Text: String = "Location"
    @State public var text129Text: String = "00/00/0000"
    @State public var text130Text: String = "Date of Birth"
    @State public var text131Text: String = "bruceli"
    @State public var text132Text: String = "Bruce"
    @State public var text133Text: String = "Li"
    @State public var text134Text: String = "Male"
    @State public var text135Text: String = "China"
    @State public var text136Text: String = "Last name"
    @State public var image173Path: String = "image173_4853"
    @State public var image174Path: String = "image174_4854"
    @State public var image175Path: String = "image175_4856"
    @State public var image176Path: String = "image176_4858"
    @State public var image177Path: String = "image177_4859"
    @State public var text137Text: String = "Upload a new avatar"
    @State public var text138Text: String = "Make an avatar with Alice"
    @State public var image178Path: String = "image178_4867"
    @State public var text139Text: String = "Bruce Li"
    @State public var image179Path: String = "image179_I487241875"
    @State public var image180Path: String = "image180_4873"
    @State public var image181Path: String = "image181_4876"
    @State public var image182Path: String = "image182_4878"
    @State public var image183Path: String = "image183_4880"
    @State public var text140Text: String = "News"
    @State public var text141Text: String = "Bruce Li"
    @State public var image184Path: String = "image184_I488441875"
    @State public var image185Path: String = "image185_4885"
    @State public var image186Path: String = "image186_4889"
    @State public var image187Path: String = "image187_4891"
    @State public var image188Path: String = "image188_4893"
    @State public var text142Text: String = "Bruce Li"
    @State public var text143Text: String = "Following"
    @State public var text144Text: String = "Followers"
    @State public var text145Text: String = "Bruce Li"
    @State public var image189Path: String = "image189_I490141875"
    @State public var image190Path: String = "image190_4902"
    @State public var image191Path: String = "image191_4905"
    @State public var image192Path: String = "image192_4907"
    @State public var image193Path: String = "image193_4909"
    @State public var text146Text: String = "Bruce Li"
    @State public var text147Text: String = "Following"
    @State public var text148Text: String = "Followers"
    @State public var image194Path: String = "image194_4921"
    @State public var text149Text: String = "Liam"
    @State public var text150Text: String = "Hello, how are you bro~"
    @State public var text151Text: String = "09:41 PM"
    @State public var image195Path: String = "image195_4930"
    @State public var text152Text: String = "1"
    @State public var image196Path: String = "image196_4932"
    @State public var image197Path: String = "image197_4934"
    @State public var image198Path: String = "image198_4935"
    @State public var image199Path: String = "image199_4937"
    @State public var text153Text: String = "Message"
    @State public var image200Path: String = "image200_4940"
    @State public var text154Text: String = "Account"
    @State public var image201Path: String = "image201_4943"
    @State public var text155Text: String = "Home"
    @State public var image202Path: String = "image202_4946"
    @State public var text156Text: String = "Message"
    @State public var image203Path: String = "image203_4952"
    @State public var text157Text: String = "Search"
    @State public var image204Path: String = "image204_4957"
    @State public var text158Text: String = "Liam"
    @State public var text159Text: String = "Hello, how are you bro~"
    @State public var text160Text: String = "09:41 PM"
    @State public var image205Path: String = "image205_4966"
    @State public var text161Text: String = "1"
    @State public var image206Path: String = "image206_I49684957"
    @State public var text162Text: String = "Liam"
    @State public var text163Text: String = "Hello, how are you bro~"
    @State public var text164Text: String = "09:41 PM"
    @State public var image207Path: String = "image207_I49684966"
    @State public var text165Text: String = "1"
    @State public var image208Path: String = "image208_I49694957"
    @State public var text166Text: String = "Liam"
    @State public var text167Text: String = "Hello, how are you bro~"
    @State public var text168Text: String = "09:41 PM"
    @State public var image209Path: String = "image209_I49694966"
    @State public var text169Text: String = "1"
    @State public var image210Path: String = "image210_4973"
    @State public var text170Text: String = "Liam"
    @State public var text171Text: String = "Hello, how are you bro~"
    @State public var text172Text: String = "09:41 PM"
    @State public var image211Path: String = "image211_4982"
    @State public var text173Text: String = "1"
    @State public var image212Path: String = "image212_4987"
    @State public var text174Text: String = "Liam"
    @State public var text175Text: String = "Hello, how are you bro~"
    @State public var text176Text: String = "09:41 PM"
    @State public var image213Path: String = "image213_4996"
    @State public var text177Text: String = "1"
    @State public var image214Path: String = "image214_41001"
    @State public var text178Text: String = "Liam"
    @State public var text179Text: String = "Hello, how are you bro~"
    @State public var text180Text: String = "09:41 PM"
    @State public var image215Path: String = "image215_41010"
    @State public var text181Text: String = "1"
    @State public var image216Path: String = "image216_41015"
    @State public var text182Text: String = "Liam"
    @State public var text183Text: String = "Hello, how are you bro~"
    @State public var text184Text: String = "09:41 PM"
    @State public var image217Path: String = "image217_41024"
    @State public var text185Text: String = "1"
    @State public var image218Path: String = "image218_41029"
    @State public var text186Text: String = "Liam"
    @State public var text187Text: String = "Hello, how are you bro~"
    @State public var text188Text: String = "09:41 PM"
    @State public var image219Path: String = "image219_41038"
    @State public var text189Text: String = "1"
    @State public var image220Path: String = "image220_41040"
    @State public var image221Path: String = "image221_41048"
    @State public var image222Path: String = "image222_41050"
    @State public var image223Path: String = "image223_41061"
    @State public var text190Text: String = "Add as friends"
    @State public var image224Path: String = "image224_41068"
    @State public var text191Text: String = "Search"
    @State public var image225Path: String = "image225_41070"
    @State public var image226Path: String = "image226_41076"
    @State public var image227Path: String = "image227_41083"
    @State public var text192Text: String = "Bruce Li"
    @State public var image228Path: String = "image228_41093"
    @State public var text193Text: String = "Share invitation link "
    @State public var image229Path: String = "image229_41097"
    @State public var text194Text: String = "Icered contacts above"
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    @State public var image231Path: String = "image231_41110"
    @State public var image232Path: String = "image232_41114"
    @State public var text197Text: String = "Add a contact"
    @State public var image233Path: String = "image233_41121"
    @State public var text198Text: String = "Mobile phone contacts"
    @State public var image234Path: String = "image234_41125"
    @State public var text199Text: String = "Scan the code"
    @State public var image235Path: String = "image235_41132"
    @State public var image236Path: String = "image236_41134"
    @State public var image237Path: String = "image237_41229"
    @State public var image238Path: String = "image238_41234"
    @State public var text200Text: String = "Search"
    @State public var image239Path: String = "image239_41236"
    @State public var text201Text: String = "Add members"
    @State public var text202Text: String = "0/256"
    @State public var image240Path: String = "image240_41240"
    @State public var image241Path: String = "image241_41245"
    @State public var image242Path: String = "image242_41247"
    @State public var text203Text: String = "Chat message"
    @State public var image243Path: String = "image243_41250"
    @State public var image244Path: String = "image244_41255"
    @State public var image245Path: String = "image245_41257"
    @State public var text204Text: String = "Chat message"
    @State public var image246Path: String = "image246_41260"
    @State public var image247Path: String = "image247_41265"
    @State public var image248Path: String = "image248_41267"
    @State public var text205Text: String = "Lists"
    @State public var image249Path: String = "image249_41270"
    @State public var image250Path: String = "image250_41275"
    @State public var text206Text: String = "All contacts"
    @State public var text207Text: String = "4"
    @State public var image251Path: String = "image251_41288"
    @State public var image252Path: String = "image252_41292"
    @State public var image253Path: String = "image253_41294"
    @State public var text208Text: String = "Add a contact"
    @State public var text209Text: String = "Save"
    @State public var image254Path: String = "image254_41298"
    @State public var text210Text: String = "First name"
    @State public var text211Text: String = "Phone"
    @State public var text212Text: String = "China"
    @State public var text213Text: String = "+86"
    @State public var text214Text: String = "Last name"
    @State public var text215Text: String = "number"
    @State public var image255Path: String = "image255_41311"
    @State public var image256Path: String = "image256_41312"
    @State public var image257Path: String = "image257_41316"
    @State public var image258Path: String = "image258_41321"
    @State public var text216Text: String = "Search"
    @State public var image259Path: String = "image259_41323"
    @State public var text217Text: String = "Contacts"
    @State public var image260Path: String = "image260_41326"
    @State public var image261Path: String = "image261_41331"
    @State public var image262Path: String = "image262_41333"
    @State public var text218Text: String = "Settings"
    @State public var image263Path: String = "image263_41336"
    @State public var image264Path: String = "image264_41341"
    @State public var image265Path: String = "image265_41346"
    @State public var text219Text: String = "Search"
    @State public var image266Path: String = "image266_41348"
    @State public var text220Text: String = "Cancel"
    @State public var image267Path: String = "image267_41355"
    @State public var image268Path: String = "image268_41360"
    @State public var text221Text: String = "Search"
    @State public var image269Path: String = "image269_41362"
    @State public var text222Text: String = "Cancel"
    @State public var image270Path: String = "image270_41368"
    @State public var image271Path: String = "image271_41373"
    @State public var text223Text: String = "Search"
    @State public var image272Path: String = "image272_41375"
    @State public var text224Text: String = "Cancel"
    @State public var image273Path: String = "image273_41381"
    @State public var image274Path: String = "image274_41386"
    @State public var text225Text: String = "Search"
    @State public var image275Path: String = "image275_41388"
    @State public var text226Text: String = "Cancel"
    @State public var image276Path: String = "image276_41394"
    @State public var image277Path: String = "image277_41399"
    @State public var text227Text: String = "Search"
    @State public var image278Path: String = "image278_41401"
    @State public var text228Text: String = "Cancel"
    @State public var image279Path: String = "image279_41407"
    @State public var image280Path: String = "image280_41412"
    @State public var text229Text: String = "Search"
    @State public var image281Path: String = "image281_41414"
    @State public var text230Text: String = "Cancel"
    @State public var image282Path: String = "image282_41418"
    @State public var text231Text: String = "Align with the QR code for automatic recognition"
    @State public var image283Path: String = "image283_41420"
    @State public var image284Path: String = "image284_41423"
    @State public var image285Path: String = "image285_41424"
    @State public var image286Path: String = "image286_41426"
    @State public var text232Text: String = "Photos"
    @State public var image287Path: String = "image287_41437"
    @State public var image288Path: String = "image288_41441"
    @State public var text233Text: String = "All"
    @State public var image289Path: String = "image289_41444"
    @State public var image290Path: String = "image290_41448"
    @State public var text234Text: String = "Drafts"
    @State public var text235Text: String = "All"
    @State public var text236Text: String = "Video"
    @State public var text237Text: String = "Photos"
    @State public var image291Path: String = "image291_41458"
    @State public var image292Path: String = "image292_41461"
    @State public var image293Path: String = "image293_41486"
    @State public var image294Path: String = "image294_41490"
    @State public var image295Path: String = "image295_41492"
    @State public var image296Path: String = "image296_41494"
    @State public var text238Text: String = "Drafts"
    @State public var image297Path: String = "image297_41503"
    @State public var image298Path: String = "image298_41504"
    @State public var image299Path: String = "image299_41506"
    @State public var image300Path: String = "image300_41513"
    @State public var text239Text: String = "Eli"
    @State public var image301Path: String = "image301_41515"
    @State public var image302Path: String = "image302_41532"
    @State public var text240Text: String = "Uh-huh..."
    @State public var image303Path: String = "image303_41544"
    @State public var text241Text: String = "miss you"
    @State public var image304Path: String = "image304_41549"
    @State public var text242Text: String = "Hello, how are you bro~"
    @State public var text243Text: String = "2025/10/22  12:00"
    @State public var image305Path: String = "image305_41560"
    @State public var image306Path: String = "image306_41561"
    @State public var image307Path: String = "image307_41563"
    @State public var image308Path: String = "image308_41570"
    @State public var text244Text: String = "Eli"
    @State public var image309Path: String = "image309_41572"
    @State public var image310Path: String = "image310_41589"
    @State public var text245Text: String = "Uh-huh..."
    @State public var image311Path: String = "image311_41601"
    @State public var text246Text: String = "miss you"
    @State public var image312Path: String = "image312_41606"
    @State public var text247Text: String = "Hello, how are you bro~"
    @State public var text248Text: String = "2025/10/22  12:00"
    @State public var image313Path: String = "image313_41611"
    @State public var image314Path: String = "image314_41626"
    @State public var image315Path: String = "image315_41641"
    @State public var image316Path: String = "image316_41676"
    @State public var image317Path: String = "image317_41715"
    @State public var image318Path: String = "image318_41750"
    @State public var image319Path: String = "image319_41752"
    @State public var image320Path: String = "image320_41755"
    @State public var image321Path: String = "image321_I4175653003"
    @State public var image322Path: String = "image322_I4175653008"
    @State public var text249Text: String = "9:41"
    @State public var image323Path: String = "image323_41758"
    @State public var image324Path: String = "image324_41761"
    @State public var image325Path: String = "image325_41762"
    @State public var image326Path: String = "image326_41763"
    @State public var image327Path: String = "image327_41768"
    @State public var image328Path: String = "image328_41770"
    @State public var image329Path: String = "image329_I4177153003"
    @State public var image330Path: String = "image330_I4177153008"
    @State public var text250Text: String = "9:41"
    @State public var image331Path: String = "image331_41773"
    @State public var image332Path: String = "image332_41774"
    @State public var image333Path: String = "image333_41775"
    @State public var image334Path: String = "image334_41776"
    @State public var image335Path: String = "image335_41781"
    @State public var image336Path: String = "image336_41783"
    @State public var image337Path: String = "image337_I4178453003"
    @State public var image338Path: String = "image338_I4178453008"
    @State public var text251Text: String = "9:41"
    @State public var image339Path: String = "image339_41786"
    @State public var image340Path: String = "image340_41787"
    @State public var image341Path: String = "image341_41788"
    @State public var image342Path: String = "image342_41789"
    @State public var image343Path: String = "image343_41794"
    @State public var image344Path: String = "image344_41796"
    @State public var image345Path: String = "image345_I4179753003"
    @State public var image346Path: String = "image346_I4179753008"
    @State public var text252Text: String = "9:41"
    @State public var image347Path: String = "image347_41799"
    @State public var image348Path: String = "image348_41800"
    @State public var image349Path: String = "image349_41801"
    @State public var image350Path: String = "image350_41802"
    @State public var image351Path: String = "image351_41807"
    @State public var image352Path: String = "image352_41809"
    @State public var image353Path: String = "image353_I4181053003"
    @State public var image354Path: String = "image354_I4181053008"
    @State public var text253Text: String = "9:41"
    @State public var image355Path: String = "image355_41812"
    @State public var image356Path: String = "image356_41815"
    @State public var image357Path: String = "image357_41820"
    @State public var image358Path: String = "image358_41822"
    @State public var image359Path: String = "image359_I4182353003"
    @State public var image360Path: String = "image360_I4182353008"
    @State public var text254Text: String = "9:41"
    @State public var image361Path: String = "image361_41825"
    @State public var image362Path: String = "image362_41828"
    @State public var image363Path: String = "image363_41829"
    @State public var image364Path: String = "image364_41831"
    @State public var image365Path: String = "image365_I4183253003"
    @State public var image366Path: String = "image366_I4183253008"
    @State public var text255Text: String = "9:41"
    @State public var image367Path: String = "image367_41834"
    @State public var image368Path: String = "image368_41837"
    @State public var image369Path: String = "image369_41838"
    @State public var image370Path: String = "image370_41840"
    @State public var image371Path: String = "image371_I4184153003"
    @State public var image372Path: String = "image372_I4184153008"
    @State public var text256Text: String = "9:41"
    @State public var image373Path: String = "image373_41843"
    @State public var image374Path: String = "image374_41846"
    @State public var image375Path: String = "image375_41847"
    @State public var text257Text: String = "Go to the Account center"
    @State public var image376Path: String = "image376_41857"
    @State public var text258Text: String = "Account_one (Primary)"
    @State public var image377Path: String = "image377_41859"
    @State public var image378Path: String = "image378_41863"
    @State public var text259Text: String = "Add an alias account (Anonymous)"
    @State public var image379Path: String = "image379_41868"
    @State public var text260Text: String = "Bruce Li"
    @State public var image380Path: String = "image380_41872"
    @State public var text261Text: String = "Bruce Li"
    @State public var image381Path: String = "image381_41875"
    @State public var image382Path: String = "image382_41881"
    @State public var text262Text: String = "1"
    @State public var text263Text: String = "Lucy Liu"
    @State public var text264Text: String = "Morgan Stanley"
    @State public var text265Text: String = "2293"
    @State public var image388Path: String = "image388_41901"
    @State public var text266Text: String = "2"
    @State public var text267Text: String = "Lucy Liu"
    @State public var text268Text: String = "Morgan Stanley"
    @State public var text269Text: String = "2293"
    @State public var image394Path: String = "image394_41921"
    @State public var text270Text: String = "3"
    @State public var text271Text: String = "Lucy Liu"
    @State public var text272Text: String = "Morgan Stanley"
    @State public var text273Text: String = "2293"
    @State public var image400Path: String = "image400_41941"
    @State public var text274Text: String = "4"
    @State public var text275Text: String = "Lucy Liu"
    @State public var text276Text: String = "Morgan Stanley"
    @State public var text277Text: String = "2293"
    @State public var image406Path: String = "image406_41961"
    @State public var text278Text: String = "5"
    @State public var text279Text: String = "Lucy Liu"
    @State public var text280Text: String = "Morgan Stanley"
    @State public var text281Text: String = "2293"
    @State public var image412Path: String = "image412_41982"
    @State public var text282Text: String = "1"
    @State public var text283Text: String = "Lucy Liu"
    @State public var text284Text: String = "Morgan Stanley"
    @State public var text285Text: String = "2293"
    @State public var image418Path: String = "image418_42002"
    @State public var text286Text: String = "2"
    @State public var text287Text: String = "Lucy Liu"
    @State public var text288Text: String = "Morgan Stanley"
    @State public var text289Text: String = "2293"
    @State public var image424Path: String = "image424_42022"
    @State public var text290Text: String = "3"
    @State public var text291Text: String = "Lucy Liu"
    @State public var text292Text: String = "Morgan Stanley"
    @State public var text293Text: String = "2293"
    @State public var image430Path: String = "image430_42042"
    @State public var text294Text: String = "4"
    @State public var text295Text: String = "Lucy Liu"
    @State public var text296Text: String = "Morgan Stanley"
    @State public var text297Text: String = "2293"
    @State public var image436Path: String = "image436_42062"
    @State public var text298Text: String = "5"
    @State public var text299Text: String = "Lucy Liu"
    @State public var text300Text: String = "Morgan Stanley"
    @State public var text301Text: String = "2293"
    @State public var image442Path: String = "image442_42083"
    @State public var text302Text: String = "1"
    @State public var text303Text: String = "Lucy Liu"
    @State public var text304Text: String = "Morgan Stanley"
    @State public var text305Text: String = "2293"
    @State public var image448Path: String = "image448_42103"
    @State public var text306Text: String = "2"
    @State public var text307Text: String = "Lucy Liu"
    @State public var text308Text: String = "Morgan Stanley"
    @State public var text309Text: String = "2293"
    @State public var image454Path: String = "image454_42123"
    @State public var text310Text: String = "3"
    @State public var text311Text: String = "Lucy Liu"
    @State public var text312Text: String = "Morgan Stanley"
    @State public var text313Text: String = "2293"
    @State public var image460Path: String = "image460_42143"
    @State public var text314Text: String = "4"
    @State public var text315Text: String = "Lucy Liu"
    @State public var text316Text: String = "Morgan Stanley"
    @State public var text317Text: String = "2293"
    @State public var image466Path: String = "image466_42163"
    @State public var text318Text: String = "5"
    @State public var text319Text: String = "Lucy Liu"
    @State public var text320Text: String = "Morgan Stanley"
    @State public var text321Text: String = "2293"
    @State public var image472Path: String = "image472_42184"
    @State public var text322Text: String = "1"
    @State public var text323Text: String = "Lucy Liu"
    @State public var text324Text: String = "Morgan Stanley"
    @State public var text325Text: String = "2293"
    @State public var image478Path: String = "image478_42204"
    @State public var text326Text: String = "2"
    @State public var text327Text: String = "Lucy Liu"
    @State public var text328Text: String = "Morgan Stanley"
    @State public var text329Text: String = "2293"
    @State public var image484Path: String = "image484_42224"
    @State public var text330Text: String = "3"
    @State public var text331Text: String = "Lucy Liu"
    @State public var text332Text: String = "Morgan Stanley"
    @State public var text333Text: String = "2293"
    @State public var image490Path: String = "image490_42244"
    @State public var text334Text: String = "4"
    @State public var text335Text: String = "Lucy Liu"
    @State public var text336Text: String = "Morgan Stanley"
    @State public var text337Text: String = "2293"
    @State public var image496Path: String = "image496_42264"
    @State public var text338Text: String = "5"
    @State public var text339Text: String = "Lucy Liu"
    @State public var text340Text: String = "Morgan Stanley"
    @State public var text341Text: String = "2293"
    @State public var image502Path: String = "image502_42285"
    @State public var text342Text: String = "1"
    @State public var text343Text: String = "Lucy Liu"
    @State public var text344Text: String = "Morgan Stanley"
    @State public var text345Text: String = "2293"
    @State public var image508Path: String = "image508_42305"
    @State public var text346Text: String = "2"
    @State public var text347Text: String = "Lucy Liu"
    @State public var text348Text: String = "Morgan Stanley"
    @State public var text349Text: String = "2293"
    @State public var image514Path: String = "image514_42325"
    @State public var text350Text: String = "3"
    @State public var text351Text: String = "Lucy Liu"
    @State public var text352Text: String = "Morgan Stanley"
    @State public var text353Text: String = "2293"
    @State public var image520Path: String = "image520_42345"
    @State public var text354Text: String = "4"
    @State public var text355Text: String = "Lucy Liu"
    @State public var text356Text: String = "Morgan Stanley"
    @State public var text357Text: String = "2293"
    @State public var image526Path: String = "image526_42365"
    @State public var text358Text: String = "5"
    @State public var text359Text: String = "Lucy Liu"
    @State public var text360Text: String = "Morgan Stanley"
    @State public var text361Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                CustomView2(
                    text1Text: text1Text,
                    text2Text: text2Text,
                    image1Path: image1Path,
                    text3Text: text3Text,
                    text4Text: text4Text,
                    text5Text: text5Text,
                    text6Text: text6Text,
                    image7Path: image7Path,
                    text7Text: text7Text,
                    text8Text: text8Text,
                    text9Text: text9Text,
                    text10Text: text10Text,
                    image13Path: image13Path,
                    text11Text: text11Text,
                    text12Text: text12Text,
                    text13Text: text13Text,
                    text14Text: text14Text,
                    image19Path: image19Path,
                    text15Text: text15Text,
                    text16Text: text16Text,
                    text17Text: text17Text,
                    text18Text: text18Text,
                    image25Path: image25Path,
                    text19Text: text19Text,
                    text20Text: text20Text,
                    text21Text: text21Text,
                    text22Text: text22Text,
                    text23Text: text23Text,
                    image31Path: image31Path,
                    image32Path: image32Path,
                    text24Text: text24Text,
                    text25Text: text25Text,
                    image33Path: image33Path,
                    image34Path: image34Path,
                    image35Path: image35Path,
                    text26Text: text26Text,
                    text27Text: text27Text,
                    text28Text: text28Text,
                    image36Path: image36Path,
                    image37Path: image37Path,
                    image38Path: image38Path,
                    text29Text: text29Text,
                    text30Text: text30Text,
                    image39Path: image39Path,
                    image40Path: image40Path,
                    image41Path: image41Path,
                    text31Text: text31Text,
                    text32Text: text32Text,
                    text33Text: text33Text,
                    image42Path: image42Path,
                    image43Path: image43Path,
                    image44Path: image44Path,
                    text34Text: text34Text,
                    text35Text: text35Text,
                    image45Path: image45Path,
                    image46Path: image46Path,
                    image47Path: image47Path,
                    text36Text: text36Text,
                    text37Text: text37Text,
                    text38Text: text38Text,
                    image48Path: image48Path,
                    image49Path: image49Path,
                    image50Path: image50Path,
                    image51Path: image51Path,
                    image52Path: image52Path,
                    image53Path: image53Path,
                    image54Path: image54Path,
                    image55Path: image55Path,
                    image56Path: image56Path,
                    image57Path: image57Path,
                    image58Path: image58Path,
                    text39Text: text39Text,
                    image59Path: image59Path,
                    text40Text: text40Text,
                    image60Path: image60Path,
                    text41Text: text41Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 4000, y: 3330)
                CustomView70(
                    image61Path: image61Path,
                    image62Path: image62Path,
                    image63Path: image63Path,
                    image64Path: image64Path,
                    image65Path: image65Path,
                    image66Path: image66Path,
                    image67Path: image67Path,
                    text42Text: text42Text,
                    text43Text: text43Text,
                    image68Path: image68Path,
                    image69Path: image69Path,
                    text44Text: text44Text,
                    text45Text: text45Text,
                    image70Path: image70Path,
                    image71Path: image71Path,
                    image72Path: image72Path,
                    text46Text: text46Text,
                    text47Text: text47Text,
                    text48Text: text48Text,
                    image73Path: image73Path,
                    text49Text: text49Text,
                    text50Text: text50Text,
                    text51Text: text51Text,
                    text52Text: text52Text,
                    text53Text: text53Text,
                    text54Text: text54Text,
                    text55Text: text55Text,
                    text56Text: text56Text,
                    image74Path: image74Path,
                    image75Path: image75Path,
                    image76Path: image76Path,
                    text57Text: text57Text,
                    text58Text: text58Text,
                    image77Path: image77Path,
                    image78Path: image78Path,
                    text59Text: text59Text,
                    text60Text: text60Text,
                    image79Path: image79Path,
                    text61Text: text61Text,
                    image80Path: image80Path,
                    text62Text: text62Text,
                    text63Text: text63Text,
                    image81Path: image81Path,
                    image82Path: image82Path,
                    text64Text: text64Text,
                    text65Text: text65Text,
                    image83Path: image83Path,
                    text66Text: text66Text,
                    text67Text: text67Text,
                    text68Text: text68Text,
                    image84Path: image84Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 2922, y: 3356)
                CustomView105(
                    text69Text: text69Text,
                    image85Path: image85Path,
                    image86Path: image86Path,
                    image87Path: image87Path,
                    text70Text: text70Text,
                    image88Path: image88Path,
                    image89Path: image89Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 2345, y: 3898)
                CustomView110(
                    text71Text: text71Text,
                    image90Path: image90Path,
                    image91Path: image91Path,
                    image92Path: image92Path,
                    text72Text: text72Text,
                    image93Path: image93Path,
                    image94Path: image94Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1918, y: 3898)
                CustomView115(
                    image95Path: image95Path,
                    image96Path: image96Path,
                    text73Text: text73Text,
                    image97Path: image97Path,
                    text74Text: text74Text,
                    text75Text: text75Text,
                    image98Path: image98Path,
                    text76Text: text76Text,
                    text77Text: text77Text,
                    image99Path: image99Path,
                    text78Text: text78Text,
                    text79Text: text79Text,
                    text80Text: text80Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 2922, y: 4297)
                CustomView129(
                    text81Text: text81Text,
                    image100Path: image100Path,
                    image101Path: image101Path,
                    image102Path: image102Path,
                    text82Text: text82Text,
                    image103Path: image103Path,
                    image104Path: image104Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 2345, y: 2988)
                CustomView134(
                    text83Text: text83Text,
                    image105Path: image105Path,
                    image106Path: image106Path,
                    image107Path: image107Path,
                    image108Path: image108Path,
                    image109Path: image109Path,
                    text84Text: text84Text,
                    image110Path: image110Path,
                    text85Text: text85Text,
                    image111Path: image111Path,
                    image112Path: image112Path,
                    text86Text: text86Text,
                    image113Path: image113Path,
                    image114Path: image114Path,
                    text87Text: text87Text,
                    image115Path: image115Path,
                    image116Path: image116Path,
                    text88Text: text88Text,
                    image117Path: image117Path,
                    image118Path: image118Path,
                    text89Text: text89Text,
                    image119Path: image119Path,
                    image120Path: image120Path,
                    text90Text: text90Text,
                    image121Path: image121Path,
                    image122Path: image122Path,
                    text91Text: text91Text,
                    image123Path: image123Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1817, y: 904)
                CustomView178(
                    text92Text: text92Text,
                    image124Path: image124Path,
                    image125Path: image125Path,
                    image126Path: image126Path,
                    image127Path: image127Path,
                    image128Path: image128Path,
                    text93Text: text93Text,
                    image129Path: image129Path,
                    text94Text: text94Text,
                    text95Text: text95Text,
                    image130Path: image130Path,
                    image131Path: image131Path,
                    text96Text: text96Text,
                    text97Text: text97Text,
                    image132Path: image132Path,
                    image133Path: image133Path,
                    text98Text: text98Text,
                    text99Text: text99Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 1371, y: 904)
                CustomView189(
                    text100Text: text100Text,
                    image134Path: image134Path,
                    image135Path: image135Path,
                    image136Path: image136Path,
                    image137Path: image137Path,
                    text101Text: text101Text,
                    image138Path: image138Path,
                    image139Path: image139Path,
                    text102Text: text102Text,
                    image140Path: image140Path,
                    image141Path: image141Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1371, y: 1808)
                CustomView199(
                    image142Path: image142Path,
                    image143Path: image143Path,
                    text103Text: text103Text,
                    text104Text: text104Text,
                    text105Text: text105Text,
                    text106Text: text106Text,
                    text107Text: text107Text,
                    text108Text: text108Text,
                    image144Path: image144Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1817, y: 1808)
            }
            Group {
                CustomView205(
                    text109Text: text109Text,
                    image145Path: image145Path,
                    image146Path: image146Path,
                    image147Path: image147Path,
                    image148Path: image148Path,
                    image149Path: image149Path,
                    text110Text: text110Text,
                    image150Path: image150Path,
                    text111Text: text111Text,
                    text112Text: text112Text,
                    image151Path: image151Path,
                    image152Path: image152Path,
                    text113Text: text113Text,
                    text114Text: text114Text,
                    image153Path: image153Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 914, y: 904)
                CustomView216(
                    text115Text: text115Text,
                    image154Path: image154Path,
                    image155Path: image155Path,
                    image156Path: image156Path,
                    image157Path: image157Path,
                    image158Path: image158Path,
                    text116Text: text116Text,
                    image159Path: image159Path,
                    text117Text: text117Text,
                    image160Path: image160Path,
                    text118Text: text118Text,
                    text119Text: text119Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 457, y: 904)
                CustomView224(
                    text120Text: text120Text,
                    image161Path: image161Path,
                    image162Path: image162Path,
                    image163Path: image163Path,
                    image164Path: image164Path,
                    image165Path: image165Path,
                    text121Text: text121Text)
                    .frame(width: 393, height: 852)
                    .offset(y: 904)
                CustomView229(
                    text122Text: text122Text,
                    image166Path: image166Path,
                    image167Path: image167Path,
                    image168Path: image168Path,
                    image169Path: image169Path,
                    image170Path: image170Path,
                    text123Text: text123Text,
                    text124Text: text124Text,
                    image171Path: image171Path,
                    image172Path: image172Path,
                    text125Text: text125Text,
                    text126Text: text126Text,
                    text127Text: text127Text,
                    text128Text: text128Text,
                    text129Text: text129Text,
                    text130Text: text130Text,
                    text131Text: text131Text,
                    text132Text: text132Text,
                    text133Text: text133Text,
                    text134Text: text134Text,
                    text135Text: text135Text,
                    text136Text: text136Text,
                    image173Path: image173Path,
                    image174Path: image174Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1371)
                CustomView242(
                    image175Path: image175Path,
                    image176Path: image176Path,
                    image177Path: image177Path,
                    text137Text: text137Text,
                    text138Text: text138Text,
                    image178Path: image178Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 914)
                CustomView245(
                    text139Text: text139Text,
                    image179Path: image179Path,
                    image180Path: image180Path,
                    image181Path: image181Path,
                    image182Path: image182Path,
                    image183Path: image183Path,
                    text140Text: text140Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 4463, y: 2298)
                CustomView250(
                    text141Text: text141Text,
                    image184Path: image184Path,
                    image185Path: image185Path,
                    image186Path: image186Path,
                    image187Path: image187Path,
                    image188Path: image188Path,
                    text142Text: text142Text,
                    text143Text: text143Text,
                    text144Text: text144Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 1487, y: 2988)
                CustomView258(
                    text145Text: text145Text,
                    image189Path: image189Path,
                    image190Path: image190Path,
                    image191Path: image191Path,
                    image192Path: image192Path,
                    image193Path: image193Path,
                    text146Text: text146Text,
                    text147Text: text147Text,
                    text148Text: text148Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 1487, y: 3898)
                CustomView266(
                    image194Path: image194Path,
                    text149Text: text149Text,
                    text150Text: text150Text,
                    text151Text: text151Text,
                    image195Path: image195Path,
                    text152Text: text152Text,
                    image196Path: image196Path,
                    image197Path: image197Path,
                    image198Path: image198Path,
                    image199Path: image199Path,
                    text153Text: text153Text,
                    image200Path: image200Path,
                    text154Text: text154Text,
                    image201Path: image201Path,
                    text155Text: text155Text,
                    image202Path: image202Path,
                    text156Text: text156Text,
                    image203Path: image203Path,
                    text157Text: text157Text,
                    image204Path: image204Path,
                    text158Text: text158Text,
                    text159Text: text159Text,
                    text160Text: text160Text,
                    image205Path: image205Path,
                    text161Text: text161Text,
                    image206Path: image206Path,
                    text162Text: text162Text,
                    text163Text: text163Text,
                    text164Text: text164Text,
                    image207Path: image207Path,
                    text165Text: text165Text,
                    image208Path: image208Path,
                    text166Text: text166Text,
                    text167Text: text167Text,
                    text168Text: text168Text,
                    image209Path: image209Path,
                    text169Text: text169Text,
                    image210Path: image210Path,
                    text170Text: text170Text,
                    text171Text: text171Text,
                    text172Text: text172Text,
                    image211Path: image211Path,
                    text173Text: text173Text,
                    image212Path: image212Path,
                    text174Text: text174Text,
                    text175Text: text175Text,
                    text176Text: text176Text,
                    image213Path: image213Path,
                    text177Text: text177Text,
                    image214Path: image214Path,
                    text178Text: text178Text,
                    text179Text: text179Text,
                    text180Text: text180Text,
                    image215Path: image215Path,
                    text181Text: text181Text,
                    image216Path: image216Path,
                    text182Text: text182Text,
                    text183Text: text183Text,
                    text184Text: text184Text,
                    image217Path: image217Path,
                    text185Text: text185Text,
                    image218Path: image218Path,
                    text186Text: text186Text,
                    text187Text: text187Text,
                    text188Text: text188Text,
                    image219Path: image219Path,
                    text189Text: text189Text,
                    image220Path: image220Path,
                    image221Path: image221Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 4000, y: 4608)
                Image(image222Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 158, height: 142, alignment: .topLeading)
                    .offset(x: 4463.17, y: 4608)
            }
            Group {
                CustomView338(
                    image223Path: image223Path,
                    text190Text: text190Text,
                    image224Path: image224Path,
                    text191Text: text191Text,
                    image225Path: image225Path,
                    image226Path: image226Path,
                    image227Path: image227Path,
                    text192Text: text192Text,
                    image228Path: image228Path,
                    text193Text: text193Text,
                    image229Path: image229Path,
                    text194Text: text194Text,
                    image230Path: image230Path,
                    text195Text: text195Text,
                    text196Text: text196Text,
                    image231Path: image231Path,
                    image232Path: image232Path,
                    text197Text: text197Text,
                    image233Path: image233Path,
                    text198Text: text198Text,
                    image234Path: image234Path,
                    text199Text: text199Text,
                    image235Path: image235Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 4827, y: 4608)
                Image(image236Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 459, alignment: .topLeading)
                    .offset(x: 5380, y: 1550)
                CustomView362(
                    image237Path: image237Path,
                    image238Path: image238Path,
                    text200Text: text200Text,
                    image239Path: image239Path,
                    text201Text: text201Text,
                    text202Text: text202Text,
                    image240Path: image240Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 4827, y: 5594)
                CustomView369(
                    image241Path: image241Path,
                    image242Path: image242Path,
                    text203Text: text203Text,
                    image243Path: image243Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 2384, y: 6682)
                CustomView373(
                    image244Path: image244Path,
                    image245Path: image245Path,
                    text204Text: text204Text,
                    image246Path: image246Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1911, y: 6682)
                CustomView377(
                    image247Path: image247Path,
                    image248Path: image248Path,
                    text205Text: text205Text,
                    image249Path: image249Path,
                    image250Path: image250Path,
                    text206Text: text206Text,
                    text207Text: text207Text,
                    image251Path: image251Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 5827, y: 5594)
                CustomView390(
                    image252Path: image252Path,
                    image253Path: image253Path,
                    text208Text: text208Text,
                    text209Text: text209Text,
                    image254Path: image254Path,
                    text210Text: text210Text,
                    text211Text: text211Text,
                    text212Text: text212Text,
                    text213Text: text213Text,
                    text214Text: text214Text,
                    text215Text: text215Text,
                    image255Path: image255Path,
                    image256Path: image256Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 5300, y: 5594)
                CustomView399(
                    image257Path: image257Path,
                    image258Path: image258Path,
                    text216Text: text216Text,
                    image259Path: image259Path,
                    text217Text: text217Text,
                    image260Path: image260Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 6300, y: 5594)
                CustomView406(
                    image261Path: image261Path,
                    image262Path: image262Path,
                    text218Text: text218Text,
                    image263Path: image263Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 6808, y: 5594)
                CustomView410(
                    image264Path: image264Path,
                    image265Path: image265Path,
                    text219Text: text219Text,
                    image266Path: image266Path,
                    text220Text: text220Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 4016, y: 5562)
            }
            Group {
                CustomView418(
                    image267Path: image267Path,
                    image268Path: image268Path,
                    text221Text: text221Text,
                    image269Path: image269Path,
                    text222Text: text222Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 5773, y: 3585)
                CustomView426(
                    image270Path: image270Path,
                    image271Path: image271Path,
                    text223Text: text223Text,
                    image272Path: image272Path,
                    text224Text: text224Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 6259, y: 3585)
                CustomView434(
                    image273Path: image273Path,
                    image274Path: image274Path,
                    text225Text: text225Text,
                    image275Path: image275Path,
                    text226Text: text226Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 6745, y: 3585)
                CustomView442(
                    image276Path: image276Path,
                    image277Path: image277Path,
                    text227Text: text227Text,
                    image278Path: image278Path,
                    text228Text: text228Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 3332, y: 4297)
                CustomView450(
                    image279Path: image279Path,
                    image280Path: image280Path,
                    text229Text: text229Text,
                    image281Path: image281Path,
                    text230Text: text230Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 4000, y: 2298)
                CustomView458(
                    image282Path: image282Path,
                    text231Text: text231Text,
                    image283Path: image283Path,
                    image284Path: image284Path,
                    image285Path: image285Path,
                    image286Path: image286Path,
                    text232Text: text232Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 5300, y: 4608)
                CustomView462(
                    image287Path: image287Path,
                    image288Path: image288Path,
                    text233Text: text233Text,
                    image289Path: image289Path,
                    image290Path: image290Path,
                    text234Text: text234Text,
                    text235Text: text235Text,
                    text236Text: text236Text,
                    text237Text: text237Text,
                    image291Path: image291Path,
                    image292Path: image292Path,
                    image293Path: image293Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 5773, y: 4608)
                CustomView471(
                    image294Path: image294Path,
                    image295Path: image295Path,
                    image296Path: image296Path,
                    text238Text: text238Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 6281, y: 4608)
                CustomView476(
                    image297Path: image297Path,
                    image298Path: image298Path,
                    image299Path: image299Path,
                    image300Path: image300Path,
                    text239Text: text239Text,
                    image301Path: image301Path,
                    image302Path: image302Path,
                    text240Text: text240Text,
                    image303Path: image303Path,
                    text241Text: text241Text,
                    image304Path: image304Path,
                    text242Text: text242Text,
                    text243Text: text243Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 2384, y: 5503)
                CustomView492(
                    image305Path: image305Path,
                    image306Path: image306Path,
                    image307Path: image307Path,
                    image308Path: image308Path,
                    text244Text: text244Text,
                    image309Path: image309Path,
                    image310Path: image310Path,
                    text245Text: text245Text,
                    image311Path: image311Path,
                    text246Text: text246Text,
                    image312Path: image312Path,
                    text247Text: text247Text,
                    text248Text: text248Text)
                    .frame(width: 393, height: 852)
                    .offset(x: 1911, y: 5503)
            }
            Group {
                Image(image313Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 304, alignment: .topLeading)
                    .offset(x: 985, y: 5657)
                Image(image314Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 304, alignment: .topLeading)
                    .offset(x: 985, y: 6170)
                Image(image315Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 153.153, height: 102.213, alignment: .topLeading)
                    .cornerRadius(5)
                    .offset(x: 4456.713, y: 4803)
                Image(image316Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 156.38, height: 98.213, alignment: .topLeading)
                    .cornerRadius(5)
                    .offset(x: 4456, y: 4963)
                Image(image317Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 135.67, height: 91.789, alignment: .topLeading)
                    .cornerRadius(5)
                    .offset(x: 4456.713, y: 5114)
                Image(image318Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 459, alignment: .topLeading)
                    .offset(x: 1438, y: 5503)
                Image(image319Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 459, alignment: .topLeading)
                    .offset(x: 1438, y: 6016)
                CustomView508(
                    image320Path: image320Path,
                    image321Path: image321Path,
                    image322Path: image322Path,
                    text249Text: text249Text,
                    image323Path: image323Path,
                    image324Path: image324Path,
                    image325Path: image325Path,
                    image326Path: image326Path,
                    image327Path: image327Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 3550, y: 5562)
                CustomView512(
                    image328Path: image328Path,
                    image329Path: image329Path,
                    image330Path: image330Path,
                    text250Text: text250Text,
                    image331Path: image331Path,
                    image332Path: image332Path,
                    image333Path: image333Path,
                    image334Path: image334Path,
                    image335Path: image335Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 1001, y: 2861)
                CustomView516(
                    image336Path: image336Path,
                    image337Path: image337Path,
                    image338Path: image338Path,
                    text251Text: text251Text,
                    image339Path: image339Path,
                    image340Path: image340Path,
                    image341Path: image341Path,
                    image342Path: image342Path,
                    image343Path: image343Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 2906, y: 5513)
            }
            Group {
                CustomView520(
                    image344Path: image344Path,
                    image345Path: image345Path,
                    image346Path: image346Path,
                    text252Text: text252Text,
                    image347Path: image347Path,
                    image348Path: image348Path,
                    image349Path: image349Path,
                    image350Path: image350Path,
                    image351Path: image351Path)
                    .frame(width: 393, height: 852)
                    .offset(x: 4437, y: 3330)
                CustomView524(
                    image352Path: image352Path,
                    image353Path: image353Path,
                    image354Path: image354Path,
                    text253Text: text253Text,
                    image355Path: image355Path,
                    image356Path: image356Path,
                    image357Path: image357Path)
                    .frame(width: 393, height: 851)
                    .offset(x: 3550, y: 6635)
                CustomView528(
                    image358Path: image358Path,
                    image359Path: image359Path,
                    image360Path: image360Path,
                    text254Text: text254Text,
                    image361Path: image361Path,
                    image362Path: image362Path,
                    image363Path: image363Path)
                    .frame(width: 393, height: 851)
                    .offset(x: 1001, y: 3934)
                CustomView532(
                    image364Path: image364Path,
                    image365Path: image365Path,
                    image366Path: image366Path,
                    text255Text: text255Text,
                    image367Path: image367Path,
                    image368Path: image368Path,
                    image369Path: image369Path)
                    .frame(width: 393, height: 851)
                    .offset(x: 2906, y: 6586)
                CustomView536(
                    image370Path: image370Path,
                    image371Path: image371Path,
                    image372Path: image372Path,
                    text256Text: text256Text,
                    image373Path: image373Path,
                    image374Path: image374Path,
                    image375Path: image375Path)
                    .frame(width: 393, height: 851)
                    .offset(x: 4863, y: 3347)
                CustomView540(
                    text257Text: text257Text,
                    image376Path: image376Path,
                    text258Text: text258Text,
                    image377Path: image377Path,
                    image378Path: image378Path,
                    text259Text: text259Text,
                    image379Path: image379Path)
                    .frame(width: 393, height: 334)
                    .offset(x: 2922, y: 2816)
                CustomView549(
                    text260Text: text260Text,
                    image380Path: image380Path,
                    text261Text: text261Text,
                    image381Path: image381Path)
                    .frame(width: 140, height: 91)
                    .offset(x: 2598, y: 2816)
                CustomView552(
                    image382Path: image382Path,
                    text262Text: text262Text,
                    text263Text: text263Text,
                    text264Text: text264Text,
                    text265Text: text265Text,
                    image388Path: image388Path,
                    text266Text: text266Text,
                    text267Text: text267Text,
                    text268Text: text268Text,
                    text269Text: text269Text,
                    image394Path: image394Path,
                    text270Text: text270Text,
                    text271Text: text271Text,
                    text272Text: text272Text,
                    text273Text: text273Text,
                    image400Path: image400Path,
                    text274Text: text274Text,
                    text275Text: text275Text,
                    text276Text: text276Text,
                    text277Text: text277Text,
                    image406Path: image406Path,
                    text278Text: text278Text,
                    text279Text: text279Text,
                    text280Text: text280Text,
                    text281Text: text281Text,
                    image412Path: image412Path,
                    text282Text: text282Text,
                    text283Text: text283Text,
                    text284Text: text284Text,
                    text285Text: text285Text,
                    image418Path: image418Path,
                    text286Text: text286Text,
                    text287Text: text287Text,
                    text288Text: text288Text,
                    text289Text: text289Text,
                    image424Path: image424Path,
                    text290Text: text290Text,
                    text291Text: text291Text,
                    text292Text: text292Text,
                    text293Text: text293Text,
                    image430Path: image430Path,
                    text294Text: text294Text,
                    text295Text: text295Text,
                    text296Text: text296Text,
                    text297Text: text297Text,
                    image436Path: image436Path,
                    text298Text: text298Text,
                    text299Text: text299Text,
                    text300Text: text300Text,
                    text301Text: text301Text,
                    image442Path: image442Path,
                    text302Text: text302Text,
                    text303Text: text303Text,
                    text304Text: text304Text,
                    text305Text: text305Text,
                    image448Path: image448Path,
                    text306Text: text306Text,
                    text307Text: text307Text,
                    text308Text: text308Text,
                    text309Text: text309Text,
                    image454Path: image454Path,
                    text310Text: text310Text,
                    text311Text: text311Text,
                    text312Text: text312Text,
                    text313Text: text313Text,
                    image460Path: image460Path,
                    text314Text: text314Text,
                    text315Text: text315Text,
                    text316Text: text316Text,
                    text317Text: text317Text,
                    image466Path: image466Path,
                    text318Text: text318Text,
                    text319Text: text319Text,
                    text320Text: text320Text,
                    text321Text: text321Text,
                    image472Path: image472Path,
                    text322Text: text322Text,
                    text323Text: text323Text,
                    text324Text: text324Text,
                    text325Text: text325Text,
                    image478Path: image478Path,
                    text326Text: text326Text,
                    text327Text: text327Text,
                    text328Text: text328Text,
                    text329Text: text329Text,
                    image484Path: image484Path,
                    text330Text: text330Text,
                    text331Text: text331Text,
                    text332Text: text332Text,
                    text333Text: text333Text,
                    image490Path: image490Path,
                    text334Text: text334Text,
                    text335Text: text335Text,
                    text336Text: text336Text,
                    text337Text: text337Text,
                    image496Path: image496Path,
                    text338Text: text338Text,
                    text339Text: text339Text,
                    text340Text: text340Text,
                    text341Text: text341Text,
                    image502Path: image502Path,
                    text342Text: text342Text,
                    text343Text: text343Text,
                    text344Text: text344Text,
                    text345Text: text345Text,
                    image508Path: image508Path,
                    text346Text: text346Text,
                    text347Text: text347Text,
                    text348Text: text348Text,
                    text349Text: text349Text,
                    image514Path: image514Path,
                    text350Text: text350Text,
                    text351Text: text351Text,
                    text352Text: text352Text,
                    text353Text: text353Text,
                    image520Path: image520Path,
                    text354Text: text354Text,
                    text355Text: text355Text,
                    text356Text: text356Text,
                    text357Text: text357Text,
                    image526Path: image526Path,
                    text358Text: text358Text,
                    text359Text: text359Text,
                    text360Text: text360Text,
                    text361Text: text361Text)
                    .frame(width: 433, height: 2204)
                    .offset(x: 8323, y: 3506)
            }
        }
        .frame(width: 8756, height: 7534, alignment: .topLeading)
    }
}

struct CustomView1_Previews: PreviewProvider {
    static var previews: some View {
        CustomView1()
    }
}
