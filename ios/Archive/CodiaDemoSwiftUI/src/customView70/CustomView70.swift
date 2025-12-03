//
//  CustomView70.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView70: View {
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
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                Rectangle()
                    .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                    .frame(width: 393, height: 852)
                Image(image61Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 805, alignment: .topLeading)
                    .offset(y: 47)
                Rectangle()
                    .fill(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 0.50))
                    .frame(width: 393, height: 805)
                    .offset(y: 47)
                Image(image62Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 394, height: 408, alignment: .topLeading)
                    .offset(y: 444)
                Rectangle()
                    .fill(Color(red: 0.96, green: 0.96, blue: 0.96, opacity: 1.00))
                    .frame(width: 393, height: 358)
                    .offset(y: 494)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 0.5))
                    .frame(width: 393, height: 1)
                    .offset(y: 494)
                Image(image63Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 72, alignment: .bottom)
                    .offset(y: 780)
                Image(image64Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 27, height: 33, alignment: .topLeading)
                    .offset(x: 256, y: 795)
                Image(image65Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 31, alignment: .topLeading)
                    .offset(x: 175, y: 796)
                Image(image66Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
            }
            Group {
                CustomView75(
                    image67Path: image67Path,
                    text42Text: text42Text)
                    .frame(width: 38, height: 42)
                    .offset(x: 103, y: 795)
                    HStack {
                        Spacer()
                            Text(text43Text)
                                .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 9))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 815)
                Image(image68Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30, alignment: .topLeading)
                    .cornerRadius(15)
                    .offset(x: 324, y: 792)
                CustomView76(
                    image69Path: image69Path,
                    text44Text: text44Text)
                    .frame(width: 38, height: 44)
                    .offset(x: 32, y: 793)
                CustomView77(
                    text45Text: text45Text,
                    image70Path: image70Path,
                    image71Path: image71Path)
                    .frame(width: 365, height: 20.99)
                    .offset(x: 14, y: 67)
                Image(image72Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18, alignment: .topLeading)
                    .offset(x: 354, y: 460)
                CustomView79(
                    text46Text: text46Text,
                    text47Text: text47Text,
                    text48Text: text48Text)
                    .frame(width: 222, height: 20)
                    .offset(x: 85, y: 459)
                CustomView80(
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
                    image75Path: image75Path)
                    .frame(width: 383, height: 263)
                    .offset(x: 5, y: 114)
                CustomView86(
                    image76Path: image76Path,
                    text57Text: text57Text,
                    text58Text: text58Text,
                    image77Path: image77Path,
                    image78Path: image78Path,
                    text59Text: text59Text,
                    text60Text: text60Text,
                    image79Path: image79Path,
                    text61Text: text61Text)
                    .frame(width: 185, height: 278)
                    .offset(x: 200, y: 498)
                CustomView94(
                    image80Path: image80Path,
                    text62Text: text62Text,
                    text63Text: text63Text,
                    image81Path: image81Path,
                    image82Path: image82Path,
                    text64Text: text64Text,
                    text65Text: text65Text,
                    image83Path: image83Path,
                    text66Text: text66Text)
                    .frame(width: 185, height: 278)
                    .offset(x: 8, y: 498)
            }
            Group {
                CustomView102(
                    text67Text: text67Text,
                    text68Text: text68Text,
                    image84Path: image84Path)
                    .frame(width: 365, height: 35)
                    .offset(x: 14, y: 393)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView70_Previews: PreviewProvider {
    static var previews: some View {
        CustomView70()
    }
}
