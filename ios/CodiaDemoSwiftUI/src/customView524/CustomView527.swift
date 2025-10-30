//
//  CustomView527.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView527: View {
    @State public var text253Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text253Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("SFProText-Semibold", size: 15))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 1)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView527_Previews: PreviewProvider {
    static var previews: some View {
        CustomView527()
    }
}
