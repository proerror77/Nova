//
//  CustomView199.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView199: View {
    @State public var image142Path: String = "image142_4740"
    @State public var image143Path: String = "image143_4742"
    @State public var text103Text: String = "Icered.com"
    @State public var text104Text: String = "Cancel"
    @State public var text105Text: String = "Log in"
    @State public var text106Text: String = "Password"
    @State public var text107Text: String = "Forget the password ?"
    @State public var text108Text: String = "Telephone, account or email"
    @State public var image144Path: String = "image144_4752"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                Rectangle()
                    .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                    .frame(width: 393, height: 113)
                Image(image142Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Image(image143Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                    HStack {
                        Spacer()
                            Text(text103Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 18))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 67)
                CustomView201(text104Text: text104Text)
                    .frame(width: 44, height: 20)
                    .offset(x: 22, y: 67.495)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: 265, height: 30)
                    .offset(x: 65, y: 269)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: 265, height: 30)
                    .offset(x: 65, y: 304)
                Rectangle()
                    .fill(Color(red: 0.87, green: 0.11, blue: 0.26, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: 265, height: 30)
                    .offset(x: 65, y: 377)
                    HStack {
                        Spacer()
                            Text(text105Text)
                                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 12))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 382)
                Text(text106Text)
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 72, y: 309)
            }
            Group {
                Text(text107Text)
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 10))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 230, y: 336)
                Text(text108Text)
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 72, y: 274)
                Image(image144Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 110, alignment: .top)
                    .offset(x: 116, y: 136)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView199_Previews: PreviewProvider {
    static var previews: some View {
        CustomView199()
    }
}
