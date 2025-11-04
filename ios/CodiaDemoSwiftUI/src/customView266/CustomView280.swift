//
//  CustomView280.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView280: View {
    @State public var text156Text: String = "Message"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text156Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 101, height: 20, alignment: .topLeading)
    }
}

struct CustomView280_Previews: PreviewProvider {
    static var previews: some View {
        CustomView280()
    }
}
